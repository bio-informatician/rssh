package p2p

import (
	"context"
	"encoding/json"
	"fmt"
	"sync"

	"github.com/pion/webrtc/v4"
)

// DefaultSTUNServers lists public STUN servers for NAT discovery
var DefaultSTUNServers = []string{
	"stun:stun.l.google.com:19302",
	"stun:stun1.l.google.com:19302",
	"stun:stun.cloudflare.com:3478",
}

// SignalPayload contains either an SDP offer/answer or an ICE candidate
type SignalPayload struct {
	Type      string                     `json:"type"` // "offer", "answer", "candidate"
	SDP       *webrtc.SessionDescription `json:"sdp,omitempty"`
	Candidate *webrtc.ICECandidateInit   `json:"candidate,omitempty"`
}

// Peer coordinates WebRTC peer connection and data channel establishment
type Peer struct {
	pc          *webrtc.PeerConnection
	dc          *webrtc.DataChannel
	isInitiator bool
	onSignal    func(payloadJSON string)

	readyCh chan *DataChannelConn
	errCh   chan error
	closeCh chan struct{}
	closeMu sync.Mutex
	closed  bool
}

// NewPeer creates a new WebRTC P2P peer
func NewPeer(isInitiator bool, onSignal func(payloadJSON string)) (*Peer, error) {
	iceServers := []webrtc.ICEServer{
		{URLs: DefaultSTUNServers},
	}

	config := webrtc.Configuration{
		ICEServers: iceServers,
	}

	pc, err := webrtc.NewPeerConnection(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create webrtc peer connection: %w", err)
	}

	p := &Peer{
		pc:          pc,
		isInitiator: isInitiator,
		onSignal:    onSignal,
		readyCh:     make(chan *DataChannelConn, 1),
		errCh:       make(chan error, 1),
		closeCh:     make(chan struct{}),
	}

	// Forward ICE candidates to remote peer via signaling
	pc.OnICECandidate(func(c *webrtc.ICECandidate) {
		if c == nil {
			return
		}
		init := c.ToJSON()
		payload := SignalPayload{
			Type:      "candidate",
			Candidate: &init,
		}
		data, err := json.Marshal(payload)
		if err == nil && p.onSignal != nil {
			p.onSignal(string(data))
		}
	})

	if isInitiator {
		// Initiator creates data channel
		ordered := true
		dc, err := pc.CreateDataChannel("rssh-p2p", &webrtc.DataChannelInit{
			Ordered: &ordered,
		})
		if err != nil {
			_ = pc.Close()
			return nil, fmt.Errorf("failed to create data channel: %w", err)
		}
		p.dc = dc

		dc.OnOpen(func() {
			conn := NewDataChannelConn(pc, dc)
			select {
			case p.readyCh <- conn:
			default:
			}
		})
	} else {
		// Responder receives data channel
		pc.OnDataChannel(func(dc *webrtc.DataChannel) {
			p.dc = dc
			dc.OnOpen(func() {
				conn := NewDataChannelConn(pc, dc)
				select {
				case p.readyCh <- conn:
				default:
				}
			})
		})
	}

	return p, nil
}

// CreateOffer generates and sets local description for initiator, sending offer via onSignal
func (p *Peer) CreateOffer() error {
	offer, err := p.pc.CreateOffer(nil)
	if err != nil {
		return fmt.Errorf("failed to create offer: %w", err)
	}

	if err := p.pc.SetLocalDescription(offer); err != nil {
		return fmt.Errorf("failed to set local description: %w", err)
	}

	payload := SignalPayload{
		Type: "offer",
		SDP:  &offer,
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	if p.onSignal != nil {
		p.onSignal(string(data))
	}

	return nil
}

// HandleSignal processes an incoming signaling payload (offer, answer, or candidate)
func (p *Peer) HandleSignal(payloadJSON string) error {
	var payload SignalPayload
	if err := json.Unmarshal([]byte(payloadJSON), &payload); err != nil {
		return fmt.Errorf("invalid signal payload: %w", err)
	}

	switch payload.Type {
	case "offer":
		if payload.SDP == nil {
			return fmt.Errorf("nil offer SDP")
		}
		if err := p.pc.SetRemoteDescription(*payload.SDP); err != nil {
			return fmt.Errorf("failed to set remote description on offer: %w", err)
		}

		answer, err := p.pc.CreateAnswer(nil)
		if err != nil {
			return fmt.Errorf("failed to create answer: %w", err)
		}

		if err := p.pc.SetLocalDescription(answer); err != nil {
			return fmt.Errorf("failed to set local description on answer: %w", err)
		}

		resp := SignalPayload{
			Type: "answer",
			SDP:  &answer,
		}
		data, err := json.Marshal(resp)
		if err != nil {
			return err
		}
		if p.onSignal != nil {
			p.onSignal(string(data))
		}

	case "answer":
		if payload.SDP == nil {
			return fmt.Errorf("nil answer SDP")
		}
		if err := p.pc.SetRemoteDescription(*payload.SDP); err != nil {
			return fmt.Errorf("failed to set remote description on answer: %w", err)
		}

	case "candidate":
		if payload.Candidate == nil {
			return fmt.Errorf("nil ICE candidate")
		}
		if err := p.pc.AddICECandidate(*payload.Candidate); err != nil {
			return fmt.Errorf("failed to add ICE candidate: %w", err)
		}
	}

	return nil
}

// WaitReady waits for the direct P2P DataChannel connection to open
func (p *Peer) WaitReady(ctx context.Context) (*DataChannelConn, error) {
	select {
	case <-ctx.Done():
		return nil, ctx.Err()
	case conn := <-p.readyCh:
		return conn, nil
	case err := <-p.errCh:
		return nil, err
	}
}

// Close terminates the peer connection and data channel
func (p *Peer) Close() error {
	p.closeMu.Lock()
	defer p.closeMu.Unlock()
	if p.closed {
		return nil
	}
	p.closed = true
	close(p.closeCh)

	if p.dc != nil {
		_ = p.dc.Close()
	}
	if p.pc != nil {
		_ = p.pc.Close()
	}
	return nil
}

// ConnectionState returns the current PeerConnectionState
func (p *Peer) ConnectionState() webrtc.PeerConnectionState {
	return p.pc.ConnectionState()
}
