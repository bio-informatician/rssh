package audit

import (
	"os"
	"path/filepath"
	"strings"
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

	content := string(data)
	if !strings.Contains(content, "EVENT=SESSION_CONNECTED") || !strings.Contains(content, "CLIENT=123-456-789") {
		t.Fatalf("audit entry missing expected fields: %s", content)
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
