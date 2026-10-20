// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package daemon

import (
	"bytes"
	"os"
	"strings"
	"testing"
)

func TestQueueAndFlushNotices(t *testing.T) {
	tmpHome := t.TempDir()
	origHome := os.Getenv("HOME")
	_ = os.Setenv("HOME", tmpHome)
	defer os.Setenv("HOME", origHome)

	// Queue notices
	QueueNotice("Inbound connection from 123-456-789 (Session: abc12345)")
	QueueNotice("Rejected connection from blocked client 999-000-111")

	var buf bytes.Buffer
	count := FlushPendingNotices(&buf)
	if count != 2 {
		t.Fatalf("expected 2 flushed notices, got %d", count)
	}

	out := buf.String()
	if !strings.Contains(out, "PENDING SECURITY NOTICES") {
		t.Fatalf("missing header in output: %s", out)
	}
	if !strings.Contains(out, "123-456-789") || !strings.Contains(out, "999-000-111") {
		t.Fatalf("output missing notice content: %s", out)
	}

	// Subsequent flush should be empty
	var buf2 bytes.Buffer
	count2 := FlushPendingNotices(&buf2)
	if count2 != 0 {
		t.Fatalf("expected 0 notices on second flush, got %d", count2)
	}
}

func TestBroadcastSecurityNotice(t *testing.T) {
	tmpHome := t.TempDir()
	origHome := os.Getenv("HOME")
	_ = os.Setenv("HOME", tmpHome)
	defer os.Setenv("HOME", origHome)

	// Call broadcast - if no active terminal can be written, it must queue
	_ = BroadcastSecurityNotice("Unauthorized probe detected")

	var buf bytes.Buffer
	count := FlushPendingNotices(&buf)
	// Either broadcast succeeded on an active pts or queued it
	if count > 0 {
		if !strings.Contains(buf.String(), "Unauthorized probe detected") {
			t.Fatalf("queued notice content mismatch: %s", buf.String())
		}
	}
}

func TestActivePTSDevices(t *testing.T) {
	devices := ActivePTSDevices()
	_ = HasActiveSessions()
	// Should return a valid slice without panicking
	t.Logf("Active PTS devices discovered: %v", devices)
}

