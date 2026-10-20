// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package audit

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func TestAuditLogger(t *testing.T) {
	tmpDir := t.TempDir()
	logPath := filepath.Join(tmpDir, "audit.log")

	logger := NewLogger(logPath)
	err := logger.Log(EventSessionConnected, "123-456-789", "sess_abc", "Direct P2P", "Authorized successfully")
	if err != nil {
		t.Fatalf("Log failed: %v", err)
	}

	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("failed to read log: %v", err)
	}

	var entry Entry
	if err := json.Unmarshal(data, &entry); err != nil {
		t.Fatalf("failed to parse JSON audit log entry: %v", err)
	}

	if entry.Event != EventSessionConnected || entry.ClientID != "123-456-789" || entry.SessionID != "sess_abc" {
		t.Fatalf("audit entry mismatch: %+v", entry)
	}
}

func TestBlocklist(t *testing.T) {
	tmpDir := t.TempDir()
	blockPath := filepath.Join(tmpDir, "blocked_clients")

	b := NewBlocklist(blockPath)

	clientID := "999-888-777"
	if b.IsBlocked(clientID) {
		t.Fatal("client should not be blocked initially")
	}

	if err := b.Block(clientID); err != nil {
		t.Fatalf("Block failed: %v", err)
	}

	if !b.IsBlocked(clientID) {
		t.Fatal("client should be blocked after Block()")
	}

	// Reload from disk
	b2 := NewBlocklist(blockPath)
	if !b2.IsBlocked(clientID) {
		t.Fatal("client should remain blocked after reload")
	}

	// Unblock
	if err := b.Unblock(clientID); err != nil {
		t.Fatalf("Unblock failed: %v", err)
	}

	if b.IsBlocked(clientID) {
		t.Fatal("client should be unblocked")
	}
}

func TestBlocklistListAndComments(t *testing.T) {
	tmpDir := t.TempDir()
	blockPath := filepath.Join(tmpDir, "blocked_clients")

	content := "# Comment line\n\n111-222-333\n# Another comment\n444-555-666\n"
	if err := os.WriteFile(blockPath, []byte(content), 0600); err != nil {
		t.Fatalf("failed to write test blocklist: %v", err)
	}

	b := NewBlocklist(blockPath)
	list := b.List()
	if len(list) != 2 {
		t.Fatalf("expected 2 blocked clients, got %d: %v", len(list), list)
	}
	if !b.IsBlocked("111-222-333") || !b.IsBlocked("444-555-666") {
		t.Error("expected loaded clients to be blocked")
	}
}
