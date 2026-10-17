package sshserver

import (
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"sync"

	"github.com/creack/pty"
	"github.com/gliderlabs/ssh"
	"github.com/pkg/sftp"
	gossh "golang.org/x/crypto/ssh"
)

// Server encapsulates the embedded OpenSSH-compatible server
type Server struct {
	server   *ssh.Server
	listener *VirtualListener
	closeMu  sync.Mutex
	isClosed bool
}

// NewServer initializes an embedded SSH server with SFTP and PTY support
func NewServer() (*Server, error) {
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("failed to generate host key: %w", err)
	}

	signer, err := gossh.NewSignerFromKey(priv)
	if err != nil {
		return nil, fmt.Errorf("failed to create signer from host key: %w", err)
	}

	forwardHandler := &ssh.ForwardedTCPHandler{}
	s := &ssh.Server{
		HostSigners: []ssh.Signer{signer},
		PasswordHandler: func(ctx ssh.Context, password string) bool {
			return true // Authenticated via Zero-Knowledge PAKE transport
		},
		PublicKeyHandler: func(ctx ssh.Context, key ssh.PublicKey) bool {
			return true
		},
		LocalPortForwardingCallback: func(ctx ssh.Context, dHost string, dPort uint32) bool {
			return true
		},
		ReversePortForwardingCallback: func(ctx ssh.Context, bHost string, bPort uint32) bool {
			return true
		},
		ChannelHandlers: map[string]ssh.ChannelHandler{
			"session":      ssh.DefaultSessionHandler,
			"direct-tcpip": ssh.DirectTCPIPHandler,
		},
		SubsystemHandlers: map[string]ssh.SubsystemHandler{
			"sftp": func(sess ssh.Session) {
				sftpServer, err := sftp.NewServer(sess)
				if err != nil {
					return
				}
				_ = sftpServer.Serve()
			},
		},
		Handler: defaultSessionHandler,
	}

	s.RequestHandlers = map[string]ssh.RequestHandler{
		"tcpip-forward":        forwardHandler.HandleSSHRequest,
		"cancel-tcpip-forward": forwardHandler.HandleSSHRequest,
	}

	vListener := NewVirtualListener()

	srv := &Server{
		server:   s,
		listener: vListener,
	}

	go func() {
		_ = s.Serve(vListener)
	}()

	return srv, nil
}

func defaultSessionHandler(sess ssh.Session) {
	shell := os.Getenv("SHELL")
	if shell == "" {
		shell = "/bin/bash"
		if _, err := os.Stat(shell); err != nil {
			shell = "/bin/sh"
		}
	}

	ptyReq, winCh, isPty := sess.Pty()
	if isPty {
		cmd := exec.Command(shell)
		cmd.Env = append(cmd.Env, os.Environ()...)
		cmd.Env = append(cmd.Env, sess.Environ()...)

		ws := &pty.Winsize{
			Cols: uint16(ptyReq.Window.Width),
			Rows: uint16(ptyReq.Window.Height),
		}
		if ws.Cols == 0 {
			ws.Cols = 80
		}
		if ws.Rows == 0 {
			ws.Rows = 24
		}

		ptyFile, err := pty.StartWithSize(cmd, ws)
		if err != nil {
			_, _ = io.WriteString(sess, fmt.Sprintf("failed to spawn pty: %v\r\n", err))
			_ = sess.Exit(1)
			return
		}
		defer func() {
			_ = ptyFile.Close()
		}()

		// Handle terminal resize dynamically
		go func() {
			for win := range winCh {
				_ = pty.Setsize(ptyFile, &pty.Winsize{
					Cols: uint16(win.Width),
					Rows: uint16(win.Height),
				})
			}
		}()

		go func() {
			_, _ = io.Copy(ptyFile, sess)
		}()
		_, _ = io.Copy(sess, ptyFile)
		_ = cmd.Wait()
		_ = sess.Exit(0)
		return
	}

	// Exec command (used by scp, rsync, git, and remote commands)
	if len(sess.Command()) > 0 {
		cmd := exec.Command(sess.Command()[0], sess.Command()[1:]...)
		cmd.Env = append(cmd.Env, os.Environ()...)
		cmd.Env = append(cmd.Env, sess.Environ()...)
		cmd.Stdin = sess
		cmd.Stdout = sess
		cmd.Stderr = sess.Stderr()

		if err := cmd.Run(); err != nil {
			if exitErr, ok := err.(*exec.ExitError); ok {
				_ = sess.Exit(exitErr.ExitCode())
			} else {
				_ = sess.Exit(1)
			}
			return
		}
		_ = sess.Exit(0)
		return
	}

	// Non-interactive without command: start plain subshell
	cmd := exec.Command(shell)
	cmd.Env = append(cmd.Env, os.Environ()...)
	cmd.Stdin = sess
	cmd.Stdout = sess
	cmd.Stderr = sess.Stderr()
	_ = cmd.Run()
	_ = sess.Exit(0)
}

// PushStream passes an incoming yamux stream or net.Conn to the embedded SSH server
func (s *Server) PushStream(conn net.Conn) error {
	return s.listener.Push(conn)
}

// Listener returns the underlying virtual listener
func (s *Server) Listener() *VirtualListener {
	return s.listener
}

// Close stops the embedded SSH server
func (s *Server) Close() error {
	s.closeMu.Lock()
	defer s.closeMu.Unlock()
	if s.isClosed {
		return nil
	}
	s.isClosed = true
	_ = s.listener.Close()
	return s.server.Close()
}
