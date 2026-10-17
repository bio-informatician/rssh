package daemon

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
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

// BroadcastSecurityNotice broadcasts an alert to active pseudo-terminals (/dev/pts/*) or queues it if offline
func BroadcastSecurityNotice(notice string) bool {
	notifyMu.Lock()
	defer notifyMu.Unlock()

	activeNotified := false
	alertMsg := fmt.Sprintf("\r\n\a🔔 [Rakhssh Security Alert] %s\r\n", notice)

	// 1. Scan for and write to active pseudo-terminals (/dev/pts/*)
	ptsList := ActivePTSDevices()
	for _, ptsPath := range ptsList {
		f, err := os.OpenFile(ptsPath, os.O_WRONLY, 0)
		if err == nil {
			_, writeErr := f.WriteString(alertMsg)
			_ = f.Close()
			if writeErr == nil {
				activeNotified = true
			}
		}
	}

	// 2. Fallback / parallel broadcast via 'wall' equivalent if available
	if cmdPath, err := exec.LookPath("wall"); err == nil {
		cmd := exec.Command(cmdPath)
		cmd.Stdin = strings.NewReader(alertMsg)
		if err := cmd.Run(); err == nil {
			activeNotified = true
		}
	}

	// 3. If no active terminal was available to receive the broadcast, queue to pending notices
	if !activeNotified {
		QueueNotice(notice)
	}

	return activeNotified
}

// ActivePTSDevices returns paths of accessible pseudo-terminals (/dev/pts/*)
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
		if f, err := os.OpenFile(ptsPath, os.O_WRONLY, 0); err == nil {
			_ = f.Close()
			active = append(active, ptsPath)
		}
	}
	return active
}

// HasActiveSessions checks if any pseudo-terminals are currently active
func HasActiveSessions() bool {
	return len(ActivePTSDevices()) > 0
}

// QueueNotice appends an alert to the pending notices file and system MOTD if available
func QueueNotice(notice string) {
	queuePath := PendingNoticesPath()
	_ = os.MkdirAll(filepath.Dir(queuePath), 0700)

	timestamp := time.Now().UTC().Format(time.RFC3339)
	line := fmt.Sprintf("[%s] %s\n", timestamp, notice)

	f, err := os.OpenFile(queuePath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0600)
	if err == nil {
		_, _ = f.WriteString(line)
		_ = f.Close()
	}

	// Also attempt to append to system or user MOTD if writable
	home, _ := os.UserHomeDir()
	motdPaths := []string{
		filepath.Join(home, ".motd"),
		"/run/motd.dynamic",
		"/etc/motd",
	}
	for _, mPath := range motdPaths {
		if mPath == "" {
			continue
		}
		if mf, err := os.OpenFile(mPath, os.O_APPEND|os.O_WRONLY, 0644); err == nil {
			_, _ = mf.WriteString(fmt.Sprintf("🔔 [Rakhssh Alert] %s", line))
			_ = mf.Close()
			break
		}
	}
}

// FlushPendingNotices reads, prints, and clears all queued security notices
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

	// Truncate / clear file
	_ = os.WriteFile(queuePath, []byte{}, 0600)

	// Clean user MOTD if present
	home, _ := os.UserHomeDir()
	userMotd := filepath.Join(home, ".motd")
	if _, err := os.Stat(userMotd); err == nil {
		_ = os.Remove(userMotd)
	}

	return len(lines)
}
