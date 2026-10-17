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
	id     string
	host   *wsConn
	client *wsConn
	mu     sync.Mutex
}

// Server coordinates signaling and fallback relaying between hosts and clients
type Server struct {
	hosts       map[string]*wsConn
	sessions    map[string]*sessionPair
	rateLimiter *RateLimiter
	mu          sync.RWMutex
}

// NewServer creates a new signaling and relay server instance
func NewServer() *Server {
	return &Server{
		hosts:       make(map[string]*wsConn),
		sessions:    make(map[string]*sessionPair),
		rateLimiter: NewRateLimiter(30, 1*time.Minute), // 30 connection requests/min per IP
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

		sessionID := generateSessionID()
		pair := &sessionPair{
			id:     sessionID,
			host:   hostConn,
			client: c,
		}
		c.sessionID = sessionID
		s.sessions[sessionID] = pair
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
	}
}

func (s *Server) closeSession(sessionID string) {
	s.mu.Lock()
	pair, exists := s.sessions[sessionID]
	if exists {
		delete(s.sessions, sessionID)
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
	}

	if c.sessionID != "" {
		if pair, ok := s.sessions[c.sessionID]; ok {
			delete(s.sessions, c.sessionID)
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
