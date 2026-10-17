package transport

import (
	"context"
	"fmt"
	"net"
	"sync"
	"time"

	"github.com/hashicorp/yamux"
	"rssh/pkg/crypto"
)

// TransportType identifies whether the underlying tunnel is direct P2P or Relay
type TransportType string

const (
	TransportTypeRelay TransportType = "WSS Relay (Stealth)"
	TransportTypeP2P   TransportType = "Direct P2P (WebRTC DataChannel)"
)

// Session represents a fully negotiated, end-to-end encrypted, multiplexed session
type Session struct {
	Type       TransportType
	SecureConn *crypto.SecureConn
	Yamux      *yamux.Session
	Latency    time.Duration
	isHost     bool

	idleTimeout time.Duration
	hardLimit   time.Duration
	idleTimer   *time.Timer
	hardTimer   *time.Timer
	timerMu     sync.Mutex

	closeMu sync.Mutex
	closed  bool
}

// NewSession creates an encrypted multiplexed yamux session over any net.Conn
func NewSession(conn net.Conn, keys *crypto.SessionKeys, isHost bool, transportType TransportType) (*Session, error) {
	secureConn, err := crypto.NewSecureConn(conn, keys, isHost)
	if err != nil {
		return nil, fmt.Errorf("failed to wrap secure connection: %w", err)
	}

	yamuxCfg := yamux.DefaultConfig()
	yamuxCfg.EnableKeepAlive = true
	yamuxCfg.KeepAliveInterval = 15 * time.Second

	var ySession *yamux.Session
	if isHost {
		ySession, err = yamux.Server(secureConn, yamuxCfg)
	} else {
		ySession, err = yamux.Client(secureConn, yamuxCfg)
	}

	if err != nil {
		_ = secureConn.Close()
		return nil, fmt.Errorf("failed to initialize yamux multiplexer: %w", err)
	}

	return &Session{
		Type:       transportType,
		SecureConn: secureConn,
		Yamux:      ySession,
		isHost:     isHost,
	}, nil
}

// OpenStream opens a new multiplexed channel
func (s *Session) OpenStream(ctx context.Context) (net.Conn, error) {
	return s.Yamux.Open()
}

// AcceptStream accepts an incoming multiplexed channel
func (s *Session) AcceptStream() (net.Conn, error) {
	return s.Yamux.Accept()
}

// Ping measures round-trip latency across the multiplexed session
func (s *Session) Ping() (time.Duration, error) {
	return s.Yamux.Ping()
}

// SetSessionTimeouts enables local client/host idle and hard duration timeouts
func (s *Session) SetSessionTimeouts(idleTimeout, hardLimit time.Duration) {
	s.timerMu.Lock()
	defer s.timerMu.Unlock()

	s.idleTimeout = idleTimeout
	s.hardLimit = hardLimit

	if hardLimit > 0 {
		s.hardTimer = time.AfterFunc(hardLimit, func() {
			_ = s.Close()
		})
	}

	if idleTimeout > 0 {
		s.idleTimer = time.AfterFunc(idleTimeout, func() {
			_ = s.Close()
		})
	}
}

// TouchActivity resets the local idle timeout timer upon data transfer
func (s *Session) TouchActivity() {
	s.timerMu.Lock()
	defer s.timerMu.Unlock()
	if s.idleTimer != nil && s.idleTimeout > 0 {
		s.idleTimer.Reset(s.idleTimeout)
	}
}

// Close gracefully closes the session and underlying channels
func (s *Session) Close() error {
	s.closeMu.Lock()
	defer s.closeMu.Unlock()
	if s.closed {
		return nil
	}
	s.closed = true

	s.timerMu.Lock()
	if s.idleTimer != nil {
		s.idleTimer.Stop()
	}
	if s.hardTimer != nil {
		s.hardTimer.Stop()
	}
	s.timerMu.Unlock()

	if s.Yamux != nil {
		_ = s.Yamux.Close()
	}
	if s.SecureConn != nil {
		_ = s.SecureConn.Close()
	}
	return nil
}

// IsClosed checks if session is closed
func (s *Session) IsClosed() bool {
	return s.Yamux.IsClosed()
}
