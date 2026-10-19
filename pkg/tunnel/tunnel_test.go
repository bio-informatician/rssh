package tunnel

import (
	"bufio"
	"fmt"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"rssh/pkg/crypto"
	"rssh/pkg/transport"
)

func TestParseForwardSpec(t *testing.T) {
	spec1, err := ParseForwardSpec("3000:localhost:8080")
	if err != nil {
		t.Fatalf("ParseForwardSpec failed: %v", err)
	}
	if spec1.BindAddr != "127.0.0.1" || spec1.LocalPort != 3000 || spec1.RemoteHost != "localhost" || spec1.RemotePort != 8080 {
		t.Fatalf("unexpected parsed spec: %+v", spec1)
	}

	spec2, err := ParseForwardSpec("0.0.0.0:4000:10.0.0.1:9000")
	if err != nil {
		t.Fatalf("ParseForwardSpec failed: %v", err)
	}
	if spec2.BindAddr != "0.0.0.0" || spec2.LocalPort != 4000 || spec2.RemoteHost != "10.0.0.1" || spec2.RemotePort != 9000 {
		t.Fatalf("unexpected parsed spec: %+v", spec2)
	}

	_, err = ParseForwardSpec("invalid")
	if err == nil {
		t.Fatal("expected error on invalid spec")
	}
}

func TestPortForwardingAndSOCKS5(t *testing.T) {
	// 1. Start target TCP echo service
	targetLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("failed to start target listener: %v", err)
	}
	defer targetLn.Close()
	targetPort := targetLn.Addr().(*net.TCPAddr).Port

	go func() {
		for {
			c, err := targetLn.Accept()
			if err != nil {
				return
			}
			go func(conn net.Conn) {
				defer conn.Close()
				reader := bufio.NewReader(conn)
				line, _ := reader.ReadString('\n')
				if strings.TrimSpace(line) == "PING" {
					_, _ = conn.Write([]byte("PONG\n"))
				}
			}(c)
		}
	}()

	// 2. Setup loopback connection for session
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen error: %v", err)
	}
	defer ln.Close()

	cCh := make(chan net.Conn, 1)
	go func() {
		c, err := net.Dial("tcp", ln.Addr().String())
		if err == nil {
			cCh <- c
		}
	}()
	hConn, err := ln.Accept()
	if err != nil {
		t.Fatalf("accept error: %v", err)
	}
	defer hConn.Close()
	cConn := <-cCh
	defer cConn.Close()

	keys := &crypto.SessionKeys{
		HostToClientKey: make([]byte, 32),
		ClientToHostKey: make([]byte, 32),
		VerificationKey: make([]byte, 32),
	}

	var (
		hostSession   *transport.Session
		clientSession *transport.Session
		wg            sync.WaitGroup
	)
	wg.Add(2)

	go func() {
		defer wg.Done()
		hostSession, _ = transport.NewSession(hConn, keys, true, transport.TransportTypeRelay)
	}()
	go func() {
		defer wg.Done()
		clientSession, _ = transport.NewSession(cConn, keys, false, transport.TransportTypeRelay)
	}()
	wg.Wait()
	defer hostSession.Close()
	defer clientSession.Close()

	// Host loop handling incoming streams
	go func() {
		for {
			st, err := hostSession.AcceptStream()
			if err != nil {
				return
			}
			go func(s net.Conn) {
				_ = HandleIncomingStream(s)
			}(st)
		}
	}()

	mgr := NewTunnelManager(clientSession)
	defer mgr.Close()

	// 3. Test Local Port Forwarding (-L)
	fwdSpec := &ForwardSpec{
		BindAddr:   "127.0.0.1",
		LocalPort:  0, // Ephemeral port
		RemoteHost: "127.0.0.1",
		RemotePort: targetPort,
	}
	fwdLn, err := mgr.StartLocalForward(fwdSpec)
	if err != nil {
		t.Fatalf("StartLocalForward failed: %v", err)
	}
	defer fwdLn.Close()
	forwardedPort := fwdLn.Addr().(*net.TCPAddr).Port

	// Dial the forwarded port
	testConn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", forwardedPort), 3*time.Second)
	if err != nil {
		t.Fatalf("failed to dial forwarded port: %v", err)
	}
	defer testConn.Close()

	_, _ = testConn.Write([]byte("PING\n"))
	resp, err := bufio.NewReader(testConn).ReadString('\n')
	if err != nil {
		t.Fatalf("failed to read response from forwarded port: %v", err)
	}
	if strings.TrimSpace(resp) != "PONG" {
		t.Fatalf("expected 'PONG', got '%s'", resp)
	}

	// 4. Test SOCKS5 Dynamic Proxy (-D)
	socksLn, err := mgr.StartSOCKS5Proxy("127.0.0.1", 0)
	if err != nil {
		t.Fatalf("StartSOCKS5Proxy failed: %v", err)
	}
	defer socksLn.Close()
	socksPort := socksLn.Addr().(*net.TCPAddr).Port

	// Connect to SOCKS5 proxy
	sConn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", socksPort), 3*time.Second)
	if err != nil {
		t.Fatalf("dial SOCKS5 failed: %v", err)
	}
	defer sConn.Close()

	// Step 1: SOCKS5 greeting: [VER=5, NMETHODS=1, METHOD=0]
	_, _ = sConn.Write([]byte{0x05, 0x01, 0x00})
	greetingResp := make([]byte, 2)
	_, _ = sConn.Read(greetingResp)
	if greetingResp[0] != 0x05 || greetingResp[1] != 0x00 {
		t.Fatalf("unexpected socks5 greeting response: %v", greetingResp)
	}

	// Step 2: SOCKS5 CONNECT to 127.0.0.1:targetPort
	connectReq := []byte{0x05, 0x01, 0x00, 0x01, 127, 0, 0, 1, byte(targetPort >> 8), byte(targetPort & 0xff)}
	_, _ = sConn.Write(connectReq)
	connectResp := make([]byte, 10)
	_, _ = sConn.Read(connectResp)
	if connectResp[1] != 0x00 {
		t.Fatalf("socks5 connect failed: status %d", connectResp[1])
	}

	// Step 3: Send PING through SOCKS5
	_, _ = sConn.Write([]byte("PING\n"))
	socksEcho, err := bufio.NewReader(sConn).ReadString('\n')
	if err != nil {
		t.Fatalf("failed to read socks5 echo: %v", err)
	}
	if strings.TrimSpace(socksEcho) != "PONG" {
		t.Fatalf("expected 'PONG', got '%s'", socksEcho)
	}
}

func TestHandleIncomingStreamUnsupported(t *testing.T) {
	c1, c2 := net.Pipe()
	defer c1.Close()

	errCh := make(chan error, 1)
	go func() {
		errCh <- HandleIncomingStream(c2)
	}()

	// Write unsupported stream type byte (e.g. 0xFF)
	_, _ = c1.Write([]byte{0xFF})

	err := <-errCh
	if err == nil || !strings.Contains(err.Error(), "unsupported stream type") {
		t.Fatalf("expected unsupported stream type error, got: %v", err)
	}
}

func TestTunnelManagerClose(t *testing.T) {
	mgr := NewTunnelManager(nil)
	if err := mgr.Close(); err != nil {
		t.Errorf("expected no error on first Close, got: %v", err)
	}
	// Idempotent close
	if err := mgr.Close(); err != nil {
		t.Errorf("expected no error on second Close, got: %v", err)
	}
}

