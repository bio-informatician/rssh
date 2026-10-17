package signaling

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  65536,
	WriteBufferSize: 65536,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for seamless cross-environment connection
	},
}

type wsConn struct {
	conn      *websocket.Conn
	remoteIP  string
	writeMu   sync.Mutex
	isClosed  bool
	hostID    string
	sessionID string
}

func (c *wsConn) WriteMessage(msg *Message) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	if c.isClosed {
		return fmt.Errorf("connection closed")
	}
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	return c.conn.WriteMessage(websocket.TextMessage, data)
}

func (c *wsConn) Close() error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	c.isClosed = true
	return c.conn.Close()
}

type sessionPair struct {
	id           string
	hostID       string
	host         *wsConn
	client       *wsConn
	createdAt    time.Time
	lastActivity time.Time
	mu           sync.Mutex
}

// Server coordinates signaling, concurrency control, timeouts, and fallback relaying
type Server struct {
	hosts       map[string]*wsConn
	busyHosts   map[string]string // hostID -> sessionID (Single-session lock)
	sessions    map[string]*sessionPair
	rateLimiter *RateLimiter
	idleTimeout time.Duration
	maxDuration time.Duration
	stopCh      chan struct{}
	closeOnce   sync.Once
	mu          sync.RWMutex
}

// NewServer creates a new signaling and relay server instance
func NewServer() *Server {
	return NewServerWithOptions(30*time.Minute, 2*time.Hour)
}

// NewServerWithOptions initializes server with custom idle and max duration timeouts
func NewServerWithOptions(idleTimeout, maxDuration time.Duration) *Server {
	s := &Server{
		hosts:       make(map[string]*wsConn),
		busyHosts:   make(map[string]string),
		sessions:    make(map[string]*sessionPair),
		rateLimiter: NewRateLimiter(30, 1*time.Minute), // 30 requests/min per IP
		idleTimeout: idleTimeout,
		maxDuration: maxDuration,
		stopCh:      make(chan struct{}),
	}
	go s.monitorTimeouts()
	return s
}

// Close stops background monitor routines
func (s *Server) Close() {
	s.closeOnce.Do(func() {
		close(s.stopCh)
	})
}

func (s *Server) monitorTimeouts() {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-s.stopCh:
			return
		case <-ticker.C:
			now := time.Now()
			var expired []struct {
				id     string
				reason string
			}

			s.mu.RLock()
			for id, pair := range s.sessions {
				pair.mu.Lock()
				if s.idleTimeout > 0 && now.Sub(pair.lastActivity) > s.idleTimeout {
					expired = append(expired, struct {
						id     string
						reason string
					}{id: id, reason: fmt.Sprintf("session idle timeout exceeded (%v)", s.idleTimeout)})
				} else if s.maxDuration > 0 && now.Sub(pair.createdAt) > s.maxDuration {
					expired = append(expired, struct {
						id     string
						reason string
					}{id: id, reason: fmt.Sprintf("session max duration exceeded (%v)", s.maxDuration)})
				}
				pair.mu.Unlock()
			}
			s.mu.RUnlock()

			for _, exp := range expired {
				s.TerminateSession(exp.id, exp.reason)
			}
		}
	}
}

// ServeHTTP implements http.Handler for the signaling server
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// If it's not a WebSocket upgrade request, serve a stealth disguise page
	if r.Header.Get("Upgrade") != "websocket" {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`<!DOCTYPE html>
<html>
<head><title>Welcome</title></head>
<body>
<h1>Web Services Gateway</h1>
<p>Service is operating normally.</p>
</body>
</html>`))
		return
	}

	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[Signaling] WebSocket upgrade error: %v", err)
		return
	}

	c := &wsConn{
		conn:     ws,
		remoteIP: r.RemoteAddr,
	}
	go s.handleConnection(c)
}

func (s *Server) handleConnection(c *wsConn) {
	defer func() {
		s.cleanupConnection(c)
		_ = c.Close()
	}()

	// Set keepalive
	_ = c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.conn.SetPongHandler(func(string) error {
		_ = c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, payload, err := c.conn.ReadMessage()
		if err != nil {
			break
		}
		_ = c.conn.SetReadDeadline(time.Now().Add(60 * time.Second))

		var msg Message
		if err := json.Unmarshal(payload, &msg); err != nil {
			continue
		}

		s.handleMessage(c, &msg)
	}
}

func (s *Server) handleMessage(c *wsConn, msg *Message) {
	switch msg.Type {
	case TypePing:
		_ = c.WriteMessage(&Message{Type: TypePong})

	case TypeRegister:
		s.mu.Lock()
		c.hostID = msg.ID
		s.hosts[msg.ID] = c
		s.mu.Unlock()

		_ = c.WriteMessage(&Message{
			Type:   TypeRegistered,
			ID:     msg.ID,
			Status: "ok",
		})

	case TypeConnect:
		if s.rateLimiter != nil && !s.rateLimiter.Allow(c.remoteIP) {
			_ = c.WriteMessage(&Message{
				Type:  TypeError,
				Error: "rate limit exceeded: please slow down",
			})
			return
		}

		targetID := msg.TargetID
		s.mu.Lock()
		hostConn, exists := s.hosts[targetID]
		if !exists || hostConn.isClosed {
			s.mu.Unlock()
			_ = c.WriteMessage(&Message{
				Type:  TypeError,
				Error: fmt.Sprintf("host %s offline or not found", targetID),
			})
			return
		}

		// Single-Session Lock Enforcement: Reject if Host is already busy with an active session
		if activeSessionID, busy := s.busyHosts[targetID]; busy {
			s.mu.Unlock()
			_ = c.WriteMessage(&Message{
				Type:      TypeError,
				TargetID:  targetID,
				SessionID: activeSessionID,
				Error:     ErrHostBusy,
			})
			return
		}

		sessionID := generateSessionID()
		now := time.Now()
		pair := &sessionPair{
			id:           sessionID,
			hostID:       targetID,
			host:         hostConn,
			client:       c,
			createdAt:    now,
			lastActivity: now,
		}
		c.sessionID = sessionID
		s.sessions[sessionID] = pair
		s.busyHosts[targetID] = sessionID // Lock Host to this session
		s.mu.Unlock()

		// Notify Host
		_ = hostConn.WriteMessage(&Message{
			Type:      TypeIncoming,
			SessionID: sessionID,
		})

		// Notify Client
		_ = c.WriteMessage(&Message{
			Type:      TypeConnected,
			SessionID: sessionID,
		})

	case TypePAKE, TypeSignal, TypeRelay:
		s.mu.RLock()
		pair, exists := s.sessions[msg.SessionID]
		s.mu.RUnlock()
		if !exists {
			_ = c.WriteMessage(&Message{
				Type:      TypeError,
				SessionID: msg.SessionID,
				Error:     "session expired or not found",
			})
			return
		}

		pair.mu.Lock()
		pair.lastActivity = time.Now() // Update active activity timestamp
		var recipient *wsConn
		if c == pair.client {
			recipient = pair.host
		} else {
			recipient = pair.client
		}
		pair.mu.Unlock()

		if recipient != nil && !recipient.isClosed {
			_ = recipient.WriteMessage(msg)
		}

	case TypeClose:
		s.closeSession(msg.SessionID)

	case TypeTerminate:
		s.TerminateSession(msg.SessionID, "terminated by user request")
	}
}

// BroadcastTerminate pushes an immediate termination frame over WebSockets and revokes the session
func (s *Server) BroadcastTerminate(sessionID, reason string) {
	s.TerminateSession(sessionID, reason)
}

// TerminateSession revokes an active session immediately, unlocking the host and sending TypeTerminate to peers
func (s *Server) TerminateSession(sessionID, reason string) {
	s.mu.Lock()
	pair, exists := s.sessions[sessionID]
	if exists {
		delete(s.sessions, sessionID)
		if pair != nil && pair.hostID != "" {
			delete(s.busyHosts, pair.hostID) // Release Single-Session Lock
		}
	}
	s.mu.Unlock()

	if exists && pair != nil {
		pair.mu.Lock()
		termMsg := &Message{
			Type:      TypeTerminate,
			SessionID: sessionID,
			Error:     reason,
		}
		if pair.client != nil && !pair.client.isClosed {
			_ = pair.client.WriteMessage(termMsg)
		}
		if pair.host != nil && !pair.host.isClosed {
			_ = pair.host.WriteMessage(termMsg)
		}
		pair.mu.Unlock()
	}
}

func (s *Server) closeSession(sessionID string) {
	s.mu.Lock()
	pair, exists := s.sessions[sessionID]
	if exists {
		delete(s.sessions, sessionID)
		if pair != nil && pair.hostID != "" {
			delete(s.busyHosts, pair.hostID) // Release Single-Session Lock
		}
	}
	s.mu.Unlock()

	if exists && pair != nil {
		pair.mu.Lock()
		if pair.client != nil {
			_ = pair.client.WriteMessage(&Message{Type: TypeClose, SessionID: sessionID})
		}
		if pair.host != nil {
			_ = pair.host.WriteMessage(&Message{Type: TypeClose, SessionID: sessionID})
		}
		pair.mu.Unlock()
	}
}

func (s *Server) cleanupConnection(c *wsConn) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if c.hostID != "" {
		if cur, ok := s.hosts[c.hostID]; ok && cur == c {
			delete(s.hosts, c.hostID)
		}
		delete(s.busyHosts, c.hostID)
	}

	if c.sessionID != "" {
		if pair, ok := s.sessions[c.sessionID]; ok {
			delete(s.sessions, c.sessionID)
			if pair.hostID != "" {
				delete(s.busyHosts, pair.hostID)
			}
			go func(p *sessionPair) {
				p.mu.Lock()
				defer p.mu.Unlock()
				var other *wsConn
				if c == p.client {
					other = p.host
				} else {
					other = p.client
				}
				if other != nil && !other.isClosed {
					_ = other.WriteMessage(&Message{Type: TypeClose, SessionID: p.id})
				}
			}(pair)
		}
	}
}

func generateSessionID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
