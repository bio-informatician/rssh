package transport

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"time"

	"rssh/pkg/crypto"
	"rssh/pkg/p2p"
	"rssh/pkg/signaling"
)

// OrchestrateHost coordinates the PAKE handshake, key confirmation, and transport initialization on the host.
// A recover() wraps the handshake goroutine body to prevent malformed PAKE payloads from killing the process.
func OrchestrateHost(ctx context.Context, sigClient *signaling.Client, sessionID, pin string, p2pTimeout time.Duration) (sess *Session, retErr error) {
	// Catch any panic from the PAKE library (e.g. nil-pointer on malformed JSON)
	defer func() {
		if r := recover(); r != nil {
			retErr = fmt.Errorf("PAKE handshake panic (possibly malformed peer message): %v", r)
		}
	}()

	// 1. Initiate PAKE
	hostPAKE, msg1, err := crypto.StartHostPAKE(pin)
	if err != nil {
		return nil, fmt.Errorf("failed to init host pake: %w", err)
	}

	pakeMsg2Ch := make(chan []byte, 1)
	signalCh := make(chan string, 100)
	relayConn := signaling.NewRelayConn(sigClient, sessionID)

	sigClient.SetHandlers(
		nil,
		func(sid, data string) {
			if sid == sessionID {
				b, err := base64.StdEncoding.DecodeString(data)
				if err == nil {
					select {
					case pakeMsg2Ch <- b:
					default:
					}
				}
			}
		},
		func(sid, data string) {
			if sid == sessionID {
				select {
				case signalCh <- data:
				default:
				}
			}
		},
		func(sid, data string) {
			if sid == sessionID {
				_ = relayConn.PushIncomingData(data)
			}
		},
		func(sid string) {
			if sid == sessionID {
				_ = relayConn.Close()
			}
		},
	)

	// Send PAKE Msg 1 to Client
	b64Msg1 := base64.StdEncoding.EncodeToString(msg1)
	if err := sigClient.SendPAKE(sessionID, b64Msg1); err != nil {
		return nil, fmt.Errorf("failed to send host pake msg1: %w", err)
	}

	// Wait for Client PAKE Msg 2
	var msg2 []byte
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(15 * time.Second):
		return nil, errors.New("timed out waiting for client pake response")
	case msg2 = <-pakeMsg2Ch:
	}

	keys, err := hostPAKE.FinishHostPAKE(msg2)
	if err != nil {
		return nil, fmt.Errorf("host pake completion failed: %w", err)
	}

	// 1b. Key-Confirmation Exchange (prevents wrong-PIN sessions from proceeding).
	// Protocol: host sends HMAC(verificationKey, "rssh-confirm" || "host" || nonce) + nonce.
	// Client must reply with HMAC(verificationKey, "rssh-confirm" || "client" || nonce).
	// If client has a different PIN, its verificationKey differs, and the tag won't match.
	hostNonce, err := crypto.GenerateConfirmationNonce()
	if err != nil {
		return nil, fmt.Errorf("failed to generate confirmation nonce: %w", err)
	}
	hostTag := crypto.BuildConfirmationTag(keys.VerificationKey, "host", hostNonce)

	// Encode as: [tag_len(2)][tag][nonce_len(2)][nonce] and send over PAKE channel
	confirmPayload := buildConfirmFrame(hostTag, hostNonce)
	if err := sigClient.SendPAKE(sessionID, base64.StdEncoding.EncodeToString(confirmPayload)); err != nil {
		return nil, fmt.Errorf("failed to send host key-confirmation: %w", err)
	}

	// Wait for client's confirmation reply
	var clientConfirmMsg []byte
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(10 * time.Second):
		return nil, errors.New("timed out waiting for client key-confirmation")
	case clientConfirmMsg = <-pakeMsg2Ch:
	}

	clientTag, _, err := parseConfirmFrame(clientConfirmMsg)
	if err != nil {
		return nil, fmt.Errorf("invalid client key-confirmation frame: %w", err)
	}
	expectedClientTag := crypto.BuildConfirmationTag(keys.VerificationKey, "client", hostNonce)
	if !bytes.Equal(clientTag, expectedClientTag) {
		return nil, errors.New("key-confirmation failed: PIN mismatch or replay attempt")
	}

	// 2. Parallel WebRTC P2P attempt
	var (
		p2pPeer *p2p.Peer
		p2pErr  error
	)
	p2pPeer, p2pErr = p2p.NewPeer(false, func(signalJSON string) {
		_ = sigClient.SendSignal(sessionID, signalJSON)
	})

	if p2pPeer != nil {
		defer func() {
			// Always close the P2P peer after selection, regardless of which path was chosen
			_ = p2pPeer.Close()
		}()
	}

	if p2pErr == nil {
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case sig := <-signalCh:
					_ = p2pPeer.HandleSignal(sig)
				}
			}
		}()
	}

	// Try waiting for direct P2P within p2pTimeout, otherwise fallback to Relay
	if p2pPeer != nil && p2pTimeout > 0 {
		p2pCtx, cancel := context.WithTimeout(ctx, p2pTimeout)
		defer cancel()

		dcConn, err := p2pPeer.WaitReady(p2pCtx)
		if err == nil && dcConn != nil {
			probeBuf := make([]byte, 14)
			_ = dcConn.SetDeadline(time.Now().Add(500 * time.Millisecond))
			n, readErr := io.ReadFull(dcConn, probeBuf)
			if readErr == nil && string(probeBuf[:n]) == "RSSH_P2P_SYNC\n" {
				if _, ackErr := dcConn.Write([]byte("RSSH_P2P_ACK\n")); ackErr == nil {
					_ = dcConn.SetDeadline(time.Time{})
					return NewSession(dcConn, keys, true, TransportTypeP2P)
				}
			}
			_ = dcConn.SetDeadline(time.Time{})
			_ = dcConn.Close()
		}
	}

	// Fallback to stealth WSS Relay
	return NewSession(relayConn, keys, true, TransportTypeRelay)
}

// OrchestrateClient coordinates the PAKE handshake, key confirmation, and transport initialization on the client.
func OrchestrateClient(ctx context.Context, sigClient *signaling.Client, sessionID, pin string, p2pTimeout time.Duration) (sess *Session, retErr error) {
	// Catch any panic from the PAKE library
	defer func() {
		if r := recover(); r != nil {
			retErr = fmt.Errorf("PAKE handshake panic (possibly malformed peer message): %v", r)
		}
	}()

	pakeMsg1Ch := make(chan []byte, 1)
	signalCh := make(chan string, 100)
	relayConn := signaling.NewRelayConn(sigClient, sessionID)

	sigClient.SetHandlers(
		nil,
		func(sid, data string) {
			if sid == sessionID {
				b, err := base64.StdEncoding.DecodeString(data)
				if err == nil {
					select {
					case pakeMsg1Ch <- b:
					default:
					}
				}
			}
		},
		func(sid, data string) {
			if sid == sessionID {
				select {
				case signalCh <- data:
				default:
				}
			}
		},
		func(sid, data string) {
			if sid == sessionID {
				_ = relayConn.PushIncomingData(data)
			}
		},
		func(sid string) {
			if sid == sessionID {
				_ = relayConn.Close()
			}
		},
	)

	// Wait for Host PAKE Msg 1
	var msg1 []byte
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(15 * time.Second):
		return nil, errors.New("timed out waiting for host pake msg1")
	case msg1 = <-pakeMsg1Ch:
	}

	msg2, keys, err := crypto.RespondClientPAKE(pin, msg1)
	if err != nil {
		return nil, fmt.Errorf("client pake derivation failed: %w", err)
	}

	// Send PAKE Msg 2 to Host
	b64Msg2 := base64.StdEncoding.EncodeToString(msg2)
	if err := sigClient.SendPAKE(sessionID, b64Msg2); err != nil {
		return nil, fmt.Errorf("failed to send client pake msg2: %w", err)
	}

	// 1b. Key-Confirmation: receive host tag+nonce, reply with client tag
	var hostConfirmMsg []byte
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case <-time.After(10 * time.Second):
		return nil, errors.New("timed out waiting for host key-confirmation")
	case hostConfirmMsg = <-pakeMsg1Ch:
	}

	hostTag, hostNonce, err := parseConfirmFrame(hostConfirmMsg)
	if err != nil {
		return nil, fmt.Errorf("invalid host key-confirmation frame: %w", err)
	}
	expectedHostTag := crypto.BuildConfirmationTag(keys.VerificationKey, "host", hostNonce)
	if !bytes.Equal(hostTag, expectedHostTag) {
		return nil, errors.New("key-confirmation failed: PIN mismatch or replay attempt")
	}

	// Send client confirmation
	clientTag := crypto.BuildConfirmationTag(keys.VerificationKey, "client", hostNonce)
	clientConfirmPayload := buildConfirmFrame(clientTag, nil) // nonce already exchanged
	if err := sigClient.SendPAKE(sessionID, base64.StdEncoding.EncodeToString(clientConfirmPayload)); err != nil {
		return nil, fmt.Errorf("failed to send client key-confirmation: %w", err)
	}

	// 2. Parallel WebRTC P2P attempt
	var (
		p2pPeer *p2p.Peer
		p2pErr  error
	)
	p2pPeer, p2pErr = p2p.NewPeer(true, func(signalJSON string) {
		_ = sigClient.SendSignal(sessionID, signalJSON)
	})

	if p2pPeer != nil {
		defer func() {
			_ = p2pPeer.Close()
		}()
	}

	if p2pErr == nil {
		go func() {
			for {
				select {
				case <-ctx.Done():
					return
				case sig := <-signalCh:
					_ = p2pPeer.HandleSignal(sig)
				}
			}
		}()
		_ = p2pPeer.CreateOffer()
	}

	// Try waiting for direct P2P within p2pTimeout, otherwise fallback to Relay
	if p2pPeer != nil && p2pTimeout > 0 {
		p2pCtx, cancel := context.WithTimeout(ctx, p2pTimeout)
		defer cancel()

		dcConn, err := p2pPeer.WaitReady(p2pCtx)
		if err == nil && dcConn != nil {
			_ = dcConn.SetDeadline(time.Now().Add(500 * time.Millisecond))
			if _, writeErr := dcConn.Write([]byte("RSSH_P2P_SYNC\n")); writeErr == nil {
				ackBuf := make([]byte, 13)
				n, readErr := io.ReadFull(dcConn, ackBuf)
				if readErr == nil && string(ackBuf[:n]) == "RSSH_P2P_ACK\n" {
					_ = dcConn.SetDeadline(time.Time{})
					return NewSession(dcConn, keys, false, TransportTypeP2P)
				}
			}
			_ = dcConn.SetDeadline(time.Time{})
			_ = dcConn.Close()
		}
	}

	// Fallback to stealth WSS Relay
	return NewSession(relayConn, keys, false, TransportTypeRelay)
}

// buildConfirmFrame encodes [tag_len(2)][tag][nonce_len(2)][nonce]
func buildConfirmFrame(tag, nonce []byte) []byte {
	buf := make([]byte, 2+len(tag)+2+len(nonce))
	binary.BigEndian.PutUint16(buf[0:2], uint16(len(tag)))
	copy(buf[2:], tag)
	binary.BigEndian.PutUint16(buf[2+len(tag):], uint16(len(nonce)))
	copy(buf[2+len(tag)+2:], nonce)
	return buf
}

// parseConfirmFrame decodes [tag_len(2)][tag][nonce_len(2)][nonce]
func parseConfirmFrame(data []byte) (tag, nonce []byte, err error) {
	if len(data) < 4 {
		return nil, nil, errors.New("confirmation frame too short")
	}
	tagLen := int(binary.BigEndian.Uint16(data[0:2]))
	if len(data) < 2+tagLen+2 {
		return nil, nil, errors.New("confirmation frame truncated at tag")
	}
	tag = data[2 : 2+tagLen]
	nonceLen := int(binary.BigEndian.Uint16(data[2+tagLen:]))
	if len(data) < 2+tagLen+2+nonceLen {
		return nil, nil, errors.New("confirmation frame truncated at nonce")
	}
	nonce = data[2+tagLen+2 : 2+tagLen+2+nonceLen]
	return tag, nonce, nil
}
