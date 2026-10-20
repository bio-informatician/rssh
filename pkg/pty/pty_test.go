// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package pty

import (
	"net"
	"strings"
	"testing"
	"time"
)

func TestRingBuffer(t *testing.T) {
	rb := NewRingBuffer(10)

	// Write 6 bytes
	_, _ = rb.Write([]byte("abcdef"))
	if rb.Len() != 6 {
		t.Fatalf("expected len 6, got %d", rb.Len())
	}
	if string(rb.Bytes()) != "abcdef" {
		t.Fatalf("expected 'abcdef', got '%s'", rb.Bytes())
	}

	// Write 6 more bytes (total 12, exceeds capacity of 10)
	_, _ = rb.Write([]byte("ghijkl"))
	if rb.Len() != 10 {
		t.Fatalf("expected len 10, got %d", rb.Len())
	}
	// Oldest 2 bytes ('ab') should be dropped, leaving "cdefghijkl"
	if string(rb.Bytes()) != "cdefghijkl" {
		t.Fatalf("expected 'cdefghijkl', got '%s'", rb.Bytes())
	}
}

func TestTerminalSession(t *testing.T) {
	sess, err := StartSession("/bin/sh", 80, 24)
	if err != nil {
		t.Fatalf("StartSession failed: %v", err)
	}
	defer sess.Close()

	if !sess.IsRunning() {
		t.Fatal("session should be running")
	}

	clientConn, hostConn := net.Pipe()
	defer clientConn.Close()
	defer hostConn.Close()

	if err := sess.Attach(hostConn); err != nil {
		t.Fatalf("Attach failed: %v", err)
	}

	// Send echo command to PTY
	go func() {
		time.Sleep(50 * time.Millisecond)
		_, _ = clientConn.Write([]byte("echo RSSH_HELLO_WORLD\n"))
	}()

	// Read from clientConn until RSSH_HELLO_WORLD is found
	found := false
	deadline := time.Now().Add(3 * time.Second)
	buf := make([]byte, 1024)

	for time.Now().Before(deadline) {
		_ = clientConn.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
		n, err := clientConn.Read(buf)
		if n > 0 {
			if strings.Contains(string(buf[:n]), "RSSH_HELLO_WORLD") {
				found = true
				break
			}
		}
		if err != nil && !strings.Contains(err.Error(), "timeout") {
			break
		}
	}

	if !found {
		t.Fatal("did not receive command output from PTY session")
	}

	// Test Resize
	if err := sess.Resize(100, 30); err != nil {
		t.Fatalf("Resize failed: %v", err)
	}
}
