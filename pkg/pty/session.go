package pty

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"sync"

	"github.com/creack/pty"
)

// TerminalSession manages a persistent PTY process and scrollback buffer
type TerminalSession struct {
	cmd        *exec.Cmd
	ptyFile    *os.File
	ringBuffer *RingBuffer

	currentWriter io.Writer
	writerMu      sync.Mutex

	detachCh chan struct{}
	closeMu  sync.Mutex
	isClosed bool
}

// StartSession spawns a new shell inside a pseudo-terminal
func StartSession(shell string, initialCols, initialRows uint16) (*TerminalSession, error) {
	if shell == "" {
		shell = os.Getenv("SHELL")
		if shell == "" {
			shell = "/bin/bash"
			if _, err := os.Stat(shell); err != nil {
				shell = "/bin/sh"
			}
		}
	}

	cmd := exec.Command(shell)
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")

	ws := &pty.Winsize{
		Cols: initialCols,
		Rows: initialRows,
	}
	if ws.Cols == 0 {
		ws.Cols = 80
	}
	if ws.Rows == 0 {
		ws.Rows = 24
	}

	ptyFile, err := pty.StartWithSize(cmd, ws)
	if err != nil {
		return nil, fmt.Errorf("failed to start pty: %w", err)
	}

	sess := &TerminalSession{
		cmd:        cmd,
		ptyFile:    ptyFile,
		ringBuffer: NewRingBuffer(1024 * 1024), // 1MB buffer
		detachCh:   make(chan struct{}),
	}

	go sess.readLoop()

	return sess, nil
}

func (s *TerminalSession) readLoop() {
	buf := make([]byte, 4096)
	for {
		n, err := s.ptyFile.Read(buf)
		if n > 0 {
			chunk := buf[:n]
			// Store in persistent ring buffer
			_, _ = s.ringBuffer.Write(chunk)

			// Forward to active client writer if attached
			s.writerMu.Lock()
			if s.currentWriter != nil {
				_, _ = s.currentWriter.Write(chunk)
			}
			s.writerMu.Unlock()
		}

		if err != nil {
			s.closeMu.Lock()
			s.isClosed = true
			s.closeMu.Unlock()
			return
		}
	}
}

// Attach attaches a client stream, replays scrollback history, and pipes stdin
func (s *TerminalSession) Attach(stream io.ReadWriter) error {
	s.closeMu.Lock()
	if s.isClosed {
		s.closeMu.Unlock()
		return errors.New("terminal session closed")
	}
	s.closeMu.Unlock()

	// 1. Replay historical buffer
	history := s.ringBuffer.Bytes()
	if len(history) > 0 {
		if _, err := stream.Write(history); err != nil {
			return err
		}
	}

	// 2. Set current active writer
	s.writerMu.Lock()
	s.currentWriter = stream
	s.writerMu.Unlock()

	// 3. Pipe incoming stream to PTY stdin
	go func() {
		buf := make([]byte, 4096)
		for {
			n, err := stream.Read(buf)
			if n > 0 {
				if _, writeErr := s.ptyFile.Write(buf[:n]); writeErr != nil {
					break
				}
			}
			if err != nil {
				break
			}
		}

		s.writerMu.Lock()
		if s.currentWriter == stream {
			s.currentWriter = nil
		}
		s.writerMu.Unlock()
	}()

	return nil
}

// Resize updates the terminal dimensions
func (s *TerminalSession) Resize(cols, rows uint16) error {
	s.closeMu.Lock()
	defer s.closeMu.Unlock()
	if s.isClosed || s.ptyFile == nil {
		return errors.New("terminal session closed")
	}
	return pty.Setsize(s.ptyFile, &pty.Winsize{
		Cols: cols,
		Rows: rows,
	})
}

// Close terminates the PTY session and subshell
func (s *TerminalSession) Close() error {
	s.closeMu.Lock()
	defer s.closeMu.Unlock()
	if s.isClosed {
		return nil
	}
	s.isClosed = true

	if s.ptyFile != nil {
		_ = s.ptyFile.Close()
	}
	if s.cmd != nil && s.cmd.Process != nil {
		_ = s.cmd.Process.Kill()
		_ = s.cmd.Wait()
	}
	return nil
}

// IsRunning checks whether the PTY process is still active
func (s *TerminalSession) IsRunning() bool {
	s.closeMu.Lock()
	defer s.closeMu.Unlock()
	return !s.isClosed
}
