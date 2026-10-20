// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package signaling

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// Client interacts with the signaling/relay server
type Client struct {
	url     string
	conn    *websocket.Conn
	writeMu sync.Mutex

	onIncoming  func(sessionID string)
	onPAKE      func(sessionID, data string)
	onSignal    func(sessionID, data string)
	onRelay     func(sessionID, data string)
	onClose     func(sessionID string)
	onTerminate func(sessionID, reason string)
	onError     func(err error)

	registerChan map[string]chan error
	connectChan  chan string
	connectErr   chan error

	mu       sync.Mutex
	isClosed bool
	closeCh  chan struct{}
}

// Dial connects to a signaling server WebSocket endpoint
func Dial(serverURL string) (*Client, error) {
	dialer := websocket.DefaultDialer
	dialer.HandshakeTimeout = 10 * time.Second

	ws, _, err := dialer.Dial(serverURL, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to dial signaling server at %s: %w", serverURL, err)
	}

	c := &Client{
		url:          serverURL,
		conn:         ws,
		registerChan: make(map[string]chan error),
		connectChan:  make(chan string, 1),
		connectErr:   make(chan error, 1),
		closeCh:      make(chan struct{}),
	}

	go c.readPump()
	go c.pingPump()

	return c, nil
}

func (c *Client) SetHandlers(
	onIncoming func(sessionID string),
	onPAKE func(sessionID, data string),
	onSignal func(sessionID, data string),
	onRelay func(sessionID, data string),
	onClose func(sessionID string),
) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.onIncoming = onIncoming
	c.onPAKE = onPAKE
	c.onSignal = onSignal
	c.onRelay = onRelay
	c.onClose = onClose
}

func (c *Client) SetTerminationHandler(handler func(sessionID, reason string)) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.onTerminate = handler
}

func (c *Client) readPump() {
	defer func() {
		_ = c.Close()
	}()

	for {
		_, payload, err := c.conn.ReadMessage()
		if err != nil {
			return
		}

		var msg Message
		if err := json.Unmarshal(payload, &msg); err != nil {
			continue
		}

		c.dispatchMessage(&msg)
	}
}

func (c *Client) pingPump() {
	ticker := time.NewTicker(30 * time.Second) // 30-second heartbeat
	defer ticker.Stop()

	for {
		select {
		case <-c.closeCh:
			return
		case <-ticker.C:
			_ = c.WriteMessage(&Message{Type: TypePing})
		}
	}
}

func (c *Client) dispatchMessage(msg *Message) {
	// Capture handlers under the lock, then call the blocking relay handler outside
	// to prevent a deadlock: holding mu while PushIncomingData blocks on a full readCh
	// would prevent Close() (which also takes mu) from proceeding.
	c.mu.Lock()
	onRelay := c.onRelay
	onIncoming := c.onIncoming
	onPAKE := c.onPAKE
	onSignal := c.onSignal
	onClose := c.onClose
	onTerminate := c.onTerminate

	switch msg.Type {
	case TypeRegistered:
		if ch, ok := c.registerChan[msg.ID]; ok {
			ch <- nil
			delete(c.registerChan, msg.ID)
		}

	case TypeConnected:
		select {
		case c.connectChan <- msg.SessionID:
		default:
		}

	case TypeError:
		err := errors.New(msg.Error)
		select {
		case c.connectErr <- err:
		default:
		}
	}
	c.mu.Unlock()

	// Call handlers outside the lock
	switch msg.Type {
	case TypeIncoming:
		if onIncoming != nil {
			go onIncoming(msg.SessionID)
		}
	case TypePAKE:
		if onPAKE != nil {
			go onPAKE(msg.SessionID, msg.Data)
		}
	case TypeSignal:
		if onSignal != nil {
			go onSignal(msg.SessionID, msg.Data)
		}
	case TypeRelay:
		if onRelay != nil {
			// Synchronous: preserves AEAD nonce sequence ordering
			onRelay(msg.SessionID, msg.Data)
		}
	case TypeClose:
		if onClose != nil {
			go onClose(msg.SessionID)
		}
	case TypeTerminate:
		if onTerminate != nil {
			go onTerminate(msg.SessionID, msg.Error)
		}
	}
}


// WriteMessage sends a structured message to the signaling server
func (c *Client) WriteMessage(msg *Message) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()

	c.mu.Lock()
	if c.isClosed {
		c.mu.Unlock()
		return errors.New("client closed")
	}
	c.mu.Unlock()

	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	return c.conn.WriteMessage(websocket.TextMessage, data)
}

// RegisterHost registers this machine with its 9-digit ID
func (c *Client) RegisterHost(ctx context.Context, hostID string) error {
	ch := make(chan error, 1)
	c.mu.Lock()
	c.registerChan[hostID] = ch
	c.mu.Unlock()

	err := c.WriteMessage(&Message{
		Type: TypeRegister,
		ID:   hostID,
	})
	if err != nil {
		return err
	}

	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-ch:
		return err
	case <-time.After(10 * time.Second):
		return errors.New("registration timed out")
	}
}

// ConnectTarget requests connection to a target 9-digit host ID
func (c *Client) ConnectTarget(ctx context.Context, targetID string) (sessionID string, err error) {
	err = c.WriteMessage(&Message{
		Type:     TypeConnect,
		TargetID: targetID,
	})
	if err != nil {
		return "", err
	}

	select {
	case <-ctx.Done():
		return "", ctx.Err()
	case sessionID := <-c.connectChan:
		return sessionID, nil
	case err := <-c.connectErr:
		return "", err
	case <-time.After(15 * time.Second):
		return "", errors.New("connection request timed out")
	}
}

// SendPAKE forwards PAKE payload to the peer
func (c *Client) SendPAKE(sessionID string, data string) error {
	return c.WriteMessage(&Message{
		Type:      TypePAKE,
		SessionID: sessionID,
		Data:      data,
	})
}

// SendSignal forwards WebRTC SDP/ICE signal payload to the peer
func (c *Client) SendSignal(sessionID string, data string) error {
	return c.WriteMessage(&Message{
		Type:      TypeSignal,
		SessionID: sessionID,
		Data:      data,
	})
}

// SendRelay forwards fallback raw encrypted relay payload
func (c *Client) SendRelay(sessionID string, data string) error {
	return c.WriteMessage(&Message{
		Type:      TypeRelay,
		SessionID: sessionID,
		Data:      data,
	})
}

// Close closes the client connection
func (c *Client) Close() error {
	c.mu.Lock()
	if c.isClosed {
		c.mu.Unlock()
		return nil
	}
	c.isClosed = true
	close(c.closeCh)
	c.mu.Unlock()

	return c.conn.Close()
}

// RelayConn adapts the signaling WebSocket relay into a full net.Conn
type RelayConn struct {
	client    *Client
	sessionID string

	readCh   chan []byte
	readBuf  []byte
	isClosed bool
	closeCh  chan struct{}
	closeMu  sync.RWMutex
}

// NewRelayConn creates a net.Conn over the fallback WebSocket relay
func NewRelayConn(client *Client, sessionID string) *RelayConn {
	return &RelayConn{
		client:    client,
		sessionID: sessionID,
		readCh:    make(chan []byte, 1024),
		closeCh:   make(chan struct{}),
	}
}

// PushIncomingData pushes incoming base64 payload from relay message into read channel.
// It must not hold any lock while blocking on the channel send.
func (r *RelayConn) PushIncomingData(b64Data string) error {
	data, err := base64.StdEncoding.DecodeString(b64Data)
	if err != nil {
		return err
	}

	r.closeMu.RLock()
	isClosed := r.isClosed
	r.closeMu.RUnlock()

	if isClosed {
		return errors.New("relay conn closed")
	}

	// Block without holding any lock; Close() can proceed concurrently
	select {
	case r.readCh <- data:
	case <-r.closeCh:
	}
	return nil
}

func (r *RelayConn) Read(b []byte) (int, error) {
	if len(r.readBuf) > 0 {
		n := copy(b, r.readBuf)
		r.readBuf = r.readBuf[n:]
		return n, nil
	}

	select {
	case <-r.closeCh:
		return 0, io.EOF
	case data, ok := <-r.readCh:
		if !ok {
			return 0, io.EOF
		}
		n := copy(b, data)
		if n < len(data) {
			r.readBuf = data[n:]
		}
		return n, nil
	}
}

func (r *RelayConn) Write(b []byte) (int, error) {
	r.closeMu.RLock()
	if r.isClosed {
		r.closeMu.RUnlock()
		return 0, errors.New("relay conn closed")
	}
	r.closeMu.RUnlock()

	encoded := base64.StdEncoding.EncodeToString(b)
	err := r.client.SendRelay(r.sessionID, encoded)
	if err != nil {
		return 0, err
	}
	return len(b), nil
}

func (r *RelayConn) Close() error {
	r.closeMu.Lock()
	if r.isClosed {
		r.closeMu.Unlock()
		return nil
	}
	r.isClosed = true
	close(r.closeCh)
	r.closeMu.Unlock()

	_ = r.client.WriteMessage(&Message{
		Type:      TypeClose,
		SessionID: r.sessionID,
	})
	return nil
}

func (r *RelayConn) LocalAddr() net.Addr {
	return &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: 0}
}

func (r *RelayConn) RemoteAddr() net.Addr {
	return &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: 443}
}

func (r *RelayConn) SetDeadline(t time.Time) error      { return nil }
func (r *RelayConn) SetReadDeadline(t time.Time) error  { return nil }
func (r *RelayConn) SetWriteDeadline(t time.Time) error { return nil }
