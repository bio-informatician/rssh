package test

import (
	"context"
	"io"
	"net"
	"net/http/httptest"
	"os"
	"os/user"
	"strings"
	"testing"
	"time"

	gossh "golang.org/x/crypto/ssh"
	"rssh/pkg/signaling"
	"rssh/pkg/sshserver"
	"rssh/pkg/transport"
	"rssh/pkg/tunnel"
)

func TestEndToEndFullFlow(t *testing.T) {
	// 1. Launch Signaling & Relay Server
	server := signaling.NewServer()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()
	wsURL := "ws" + strings.TrimPrefix(httpServer.URL, "http")

	hostID := "111-222-333"
	pin := "8765"

	// 2. Launch Host
	hostSig, err := signaling.Dial(wsURL)
	if err != nil {
		t.Fatalf("host dial error: %v", err)
	}
	defer hostSig.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()

	if err := hostSig.RegisterHost(ctx, hostID); err != nil {
		t.Fatalf("host register error: %v", err)
	}

	sshSrv, err := sshserver.NewServer()
	if err != nil {
		t.Fatalf("ssh server error: %v", err)
	}
	defer sshSrv.Close()

	incomingCh := make(chan string, 1)
	hostSig.SetHandlers(
		func(sessionID string) {
			incomingCh <- sessionID
		},
		nil, nil, nil, nil,
	)

	// Host connection listener loop
	var hostSession *transport.Session
	go func() {
		sid := <-incomingCh
		sess, err := transport.OrchestrateHost(ctx, hostSig, sid, pin, 100*time.Millisecond)
		if err != nil {
			return
		}
		hostSession = sess

		for {
			st, err := sess.AcceptStream()
			if err != nil {
				return
			}
			go func(stream net.Conn) {
				typeBuf := make([]byte, 1)
				if _, err := io.ReadFull(stream, typeBuf); err != nil {
					_ = stream.Close()
					return
				}
				if typeBuf[0] == tunnel.StreamTypeSSH {
					_ = sshSrv.PushStream(stream)
				}
			}(st)
		}
	}()

	// 3. Client Connects
	clientSig, err := signaling.Dial(wsURL)
	if err != nil {
		t.Fatalf("client dial error: %v", err)
	}
	defer clientSig.Close()

	clientSessionID, err := clientSig.ConnectTarget(ctx, hostID)
	if err != nil {
		t.Fatalf("client connect target error: %v", err)
	}

	clientSession, err := transport.OrchestrateClient(ctx, clientSig, clientSessionID, pin, 100*time.Millisecond)
	if err != nil {
		t.Fatalf("client orchestrate error: %v", err)
	}
	defer clientSession.Close()

	// 4. Test SSH ProxyCommand Stream
	sshStream, err := clientSession.OpenStream(ctx)
	if err != nil {
		t.Fatalf("failed to open ssh stream: %v", err)
	}
	defer sshStream.Close()

	// Write SSH stream type header
	if _, err := sshStream.Write([]byte{tunnel.StreamTypeSSH}); err != nil {
		t.Fatalf("failed to write stream header: %v", err)
	}

	// Connect OpenSSH client over this stream
	sshConfig := &gossh.ClientConfig{
		User:            "testuser",
		Auth:            []gossh.AuthMethod{gossh.Password("dummy")},
		HostKeyCallback: gossh.InsecureIgnoreHostKey(),
		Timeout:         5 * time.Second,
	}

	cConn, chans, reqs, err := gossh.NewClientConn(sshStream, "127.0.0.1:2222", sshConfig)
	if err != nil {
		t.Fatalf("NewClientConn over encrypted stream failed: %v", err)
	}
	defer cConn.Close()

	sshClient := gossh.NewClient(cConn, chans, reqs)
	defer sshClient.Close()

	sess, err := sshClient.NewSession()
	if err != nil {
		t.Fatalf("ssh NewSession failed: %v", err)
	}
	defer sess.Close()

	out, err := sess.CombinedOutput("whoami")
	if err != nil {
		t.Fatalf("whoami command failed: %v", err)
	}

	currUser, _ := user.Current()
	expectedUser := os.Getenv("USER")
	if expectedUser == "" && currUser != nil {
		expectedUser = currUser.Username
	}

	if expectedUser != "" && !strings.Contains(string(out), expectedUser) {
		t.Fatalf("expected whoami to contain %s, got: %s", expectedUser, string(out))
	}

	_ = hostSession
}
