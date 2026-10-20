// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package audit

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// EventType defines the type of audit event
type EventType string

const (
	EventSessionConnected    EventType = "SESSION_CONNECTED"
	EventSessionDisconnected EventType = "SESSION_DISCONNECTED"
	EventSessionRejected     EventType = "SESSION_REJECTED"
	EventClientBlocked       EventType = "CLIENT_BLOCKED"
	EventClientUnblocked     EventType = "CLIENT_UNBLOCKED"
)

// Entry represents an individual audit log entry
type Entry struct {
	Timestamp time.Time `json:"timestamp"`
	Event     EventType `json:"event"`
	ClientID  string    `json:"client_id,omitempty"`
	SessionID string    `json:"session_id,omitempty"`
	Transport string    `json:"transport,omitempty"`
	Details   string    `json:"details,omitempty"`
}

// Logger handles local audit logging in compliance with GDPR auditability
type Logger struct {
	path string
	mu   sync.Mutex
}

// NewLogger creates an audit logger writing to ~/.config/rssh/audit.log
func NewLogger(path string) *Logger {
	if path == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			home = "."
		}
		path = filepath.Join(home, ".config", "rssh", "audit.log")
	}
	return &Logger{path: path}
}

// Log writes an audit entry with timestamp as structured JSON
func (l *Logger) Log(event EventType, clientID, sessionID, transport, details string) error {
	l.mu.Lock()
	defer l.mu.Unlock()

	dir := filepath.Dir(l.path)
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}

	f, err := os.OpenFile(l.path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer f.Close()

	entry := Entry{
		Timestamp: time.Now().UTC(),
		Event:     event,
		ClientID:  clientID,
		SessionID: sessionID,
		Transport: transport,
		Details:   details,
	}

	data, err := json.Marshal(entry)
	if err != nil {
		return err
	}

	_, err = f.WriteString(string(data) + "\n")
	return err
}

// Blocklist manages permanently banned client IDs to mitigate unauthorized access
type Blocklist struct {
	path    string
	blocked map[string]struct{}
	mu      sync.RWMutex
}

// NewBlocklist loads ~/.config/rssh/blocked_clients
func NewBlocklist(path string) *Blocklist {
	if path == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			home = "."
		}
		path = filepath.Join(home, ".config", "rssh", "blocked_clients")
	}

	b := &Blocklist{
		path:    path,
		blocked: make(map[string]struct{}),
	}
	b.load()
	return b
}

func (b *Blocklist) load() {
	b.mu.Lock()
	defer b.mu.Unlock()

	data, err := os.ReadFile(b.path)
	if err != nil {
		return
	}

	scanner := bufio.NewScanner(strings.NewReader(string(data)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		b.blocked[line] = struct{}{}
	}
}

// IsBlocked checks if a client ID is currently banned
func (b *Blocklist) IsBlocked(clientID string) bool {
	b.mu.RLock()
	defer b.mu.RUnlock()
	_, exists := b.blocked[clientID]
	return exists
}

// Block adds a client ID to the permanent ban list
func (b *Blocklist) Block(clientID string) error {
	b.mu.Lock()
	defer b.mu.Unlock()

	b.blocked[clientID] = struct{}{}
	return b.saveLocked()
}

// Unblock removes a client ID from the ban list
func (b *Blocklist) Unblock(clientID string) error {
	b.mu.Lock()
	defer b.mu.Unlock()

	delete(b.blocked, clientID)
	return b.saveLocked()
}

// List returns all currently blocked client IDs
func (b *Blocklist) List() []string {
	b.mu.RLock()
	defer b.mu.RUnlock()

	var list []string
	for id := range b.blocked {
		list = append(list, id)
	}
	return list
}

func (b *Blocklist) saveLocked() error {
	_ = os.MkdirAll(filepath.Dir(b.path), 0700)
	var sb strings.Builder
	sb.WriteString("# Rakhssh Blocked Clients (Abuse Prevention)\n")
	for id := range b.blocked {
		sb.WriteString(id + "\n")
	}
	return os.WriteFile(b.path, []byte(sb.String()), 0600)
}
