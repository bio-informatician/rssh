// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package daemon

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)


var notifyMu sync.Mutex

// PendingNoticesPath returns the path to ~/.config/rssh/pending_notices
func PendingNoticesPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		home = "."
	}
	return filepath.Join(home, ".config", "rssh", "pending_notices")
}

// BroadcastSecurityNotice writes an alert to the operator's own pseudo-terminals (/dev/pts/*).
//
// Security notes:
//   - The notice string MUST be sanitized by the caller before passing here.
//   - We do NOT call wall(1) because that would broadcast to every logged-in user on
//     the system, which is a security anti-pattern and can be exploited by a malicious server.
//   - We do NOT write to /etc/motd or /run/motd.dynamic for the same reason.
//
// Returns true if at least one active terminal received the message.
// If no terminal is reachable, the notice is queued in pending_notices.
func BroadcastSecurityNotice(notice string) bool {
	notifyMu.Lock()
	defer notifyMu.Unlock()

	activeNotified := false
	alertMsg := []byte(fmt.Sprintf("\r\n\a🔔 [Rakhssh Security Alert] %s\r\n", notice))

	// Write to active pseudo-terminals (/dev/pts/*) using raw non-blocking syscalls
	// to avoid Go netpoller runtime_pollWait hangs when a pts has no reader.
	ptsList := ActivePTSDevices()
	for _, ptsPath := range ptsList {
		fd, err := syscall.Open(ptsPath, syscall.O_WRONLY|syscall.O_NONBLOCK, 0)
		if err == nil {
			n, writeErr := syscall.Write(fd, alertMsg)
			_ = syscall.Close(fd)
			if writeErr == nil && n > 0 {
				activeNotified = true
			}
		}
	}

	// If no active terminal received the notice, queue it for the next login
	if !activeNotified {
		queueNotice(notice)
	}

	return activeNotified
}

// ActivePTSDevices returns paths of accessible pseudo-terminals (/dev/pts/*).
// Only devices that can be opened for writing in non-blocking mode are returned.
func ActivePTSDevices() []string {
	ptsDir := "/dev/pts"
	entries, err := os.ReadDir(ptsDir)
	if err != nil {
		return nil
	}

	var active []string
	for _, entry := range entries {
		name := entry.Name()
		if name == "ptmx" || strings.HasPrefix(name, ".") {
			continue
		}
		ptsPath := filepath.Join(ptsDir, name)
		if fd, err := syscall.Open(ptsPath, syscall.O_WRONLY|syscall.O_NONBLOCK, 0); err == nil {
			_ = syscall.Close(fd)
			active = append(active, ptsPath)
		}
	}
	return active
}

// HasActiveSessions checks if any pseudo-terminals are currently active.
func HasActiveSessions() bool {
	return len(ActivePTSDevices()) > 0
}

// QueueNotice appends an alert to the pending notices file.
// This is exported for use by tests and external packages.
func QueueNotice(notice string) {
	notifyMu.Lock()
	defer notifyMu.Unlock()
	queueNotice(notice)
}

// queueNotice is the internal (mutex-not-held) variant.
func queueNotice(notice string) {
	queuePath := PendingNoticesPath()
	_ = os.MkdirAll(filepath.Dir(queuePath), 0700)

	timestamp := time.Now().UTC().Format(time.RFC3339)
	line := fmt.Sprintf("[%s] %s\n", timestamp, notice)

	f, err := os.OpenFile(queuePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err == nil {
		_, _ = f.WriteString(line)
		_ = f.Close()
	}
}

// FlushPendingNotices reads, prints, and clears all queued security notices.
// It does NOT delete ~/.motd or write to system files.
func FlushPendingNotices(w io.Writer) int {
	notifyMu.Lock()
	defer notifyMu.Unlock()

	queuePath := PendingNoticesPath()
	data, err := os.ReadFile(queuePath)
	if err != nil || len(data) == 0 {
		return 0
	}

	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	if len(lines) == 0 || (len(lines) == 1 && lines[0] == "") {
		return 0
	}

	fmt.Fprintf(w, "\n⚠️  PENDING SECURITY NOTICES (While You Were Away):\n")
	for _, l := range lines {
		if strings.TrimSpace(l) != "" {
			fmt.Fprintf(w, "   └── %s\n", l)
		}
	}
	fmt.Fprintf(w, "\n")

	// Truncate / clear file after display
	_ = os.WriteFile(queuePath, []byte{}, 0600)

	return len(lines)
}
