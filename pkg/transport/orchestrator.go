package transport

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"time"

	"rssh/pkg/crypto"
	"rssh/pkg/p2p"
	"rssh/pkg/signaling"
)

// OrchestrateHost coordinates the PAKE handshake and transport initialization on the host
func OrchestrateHost(ctx context.Context, sigClient *signaling.Client, sessionID, pin string, p2pTimeout time.Duration) (*Session, error) {
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

	// 2. Parallel WebRTC P2P attempt
	var (
		p2pPeer *p2p.Peer
		p2pErr  error
	)
	p2pPeer, p2pErr = p2p.NewPeer(false, func(signalJSON string) {
		_ = sigClient.SendSignal(sessionID, signalJSON)
	})

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

// OrchestrateClient coordinates the PAKE handshake and transport initialization on the client
func OrchestrateClient(ctx context.Context, sigClient *signaling.Client, sessionID, pin string, p2pTimeout time.Duration) (*Session, error) {
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

	// 2. Parallel WebRTC P2P attempt
	var (
		p2pPeer *p2p.Peer
		p2pErr  error
	)
	p2pPeer, p2pErr = p2p.NewPeer(true, func(signalJSON string) {
		_ = sigClient.SendSignal(sessionID, signalJSON)
	})

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
