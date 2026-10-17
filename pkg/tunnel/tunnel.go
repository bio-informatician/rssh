package tunnel

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"

	"rssh/pkg/transport"
)

const (
	StreamTypeDirect = byte(0x01) // Direct port forward
	StreamTypeSOCKS5 = byte(0x02) // SOCKS5 dynamic forward
	StreamTypeSSH    = byte(0x03) // SSH ProxyCommand stream
	StreamTypePTY    = byte(0x04) // Direct interactive PTY
	StreamTypeChat   = byte(0x05) // Ephemeral end-to-end encrypted chat
)

// ForwardSpec represents a parsed port forwarding rule
type ForwardSpec struct {
	BindAddr   string
	LocalPort  int
	RemoteHost string
	RemotePort int
}

// ParseForwardSpec parses "-L [bind_addr:]port:host:hostport" syntax
func ParseForwardSpec(spec string) (*ForwardSpec, error) {
	parts := strings.Split(spec, ":")
	switch len(parts) {
	case 3:
		// port:host:hostport
		lPort, err := strconv.Atoi(parts[0])
		if err != nil {
			return nil, fmt.Errorf("invalid local port %s: %w", parts[0], err)
		}
		rPort, err := strconv.Atoi(parts[2])
		if err != nil {
			return nil, fmt.Errorf("invalid remote port %s: %w", parts[2], err)
		}
		return &ForwardSpec{
			BindAddr:   "127.0.0.1",
			LocalPort:  lPort,
			RemoteHost: parts[1],
			RemotePort: rPort,
		}, nil
	case 4:
		// bind_addr:port:host:hostport
		lPort, err := strconv.Atoi(parts[1])
		if err != nil {
			return nil, fmt.Errorf("invalid local port %s: %w", parts[1], err)
		}
		rPort, err := strconv.Atoi(parts[3])
		if err != nil {
			return nil, fmt.Errorf("invalid remote port %s: %w", parts[3], err)
		}
		return &ForwardSpec{
			BindAddr:   parts[0],
			LocalPort:  lPort,
			RemoteHost: parts[2],
			RemotePort: rPort,
		}, nil
	default:
		return nil, fmt.Errorf("invalid forward spec '%s', expected [bind_addr:]port:host:hostport", spec)
	}
}

// TunnelManager handles forwarding streams across a multiplexed Session
type TunnelManager struct {
	session  *transport.Session
	closeCh  chan struct{}
	closeMu  sync.Mutex
	isClosed bool
}

// NewTunnelManager creates a tunnel manager
func NewTunnelManager(session *transport.Session) *TunnelManager {
	return &TunnelManager{
		session: session,
		closeCh: make(chan struct{}),
	}
}

// StartLocalForward opens a local TCP listener and tunnels connections to the remote host
func (m *TunnelManager) StartLocalForward(spec *ForwardSpec) (net.Listener, error) {
	addr := fmt.Sprintf("%s:%d", spec.BindAddr, spec.LocalPort)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("failed to listen on %s: %w", addr, err)
	}

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go m.handleLocalConn(conn, spec.RemoteHost, spec.RemotePort)
		}
	}()

	return listener, nil
}

func (m *TunnelManager) handleLocalConn(conn net.Conn, targetHost string, targetPort int) {
	defer conn.Close()

	stream, err := m.session.OpenStream(nil)
	if err != nil {
		return
	}
	defer stream.Close()

	// Write forward header: [StreamTypeDirect(1)][host_len(1)][target_host][target_port(2)]
	hostBytes := []byte(targetHost)
	header := make([]byte, 1+1+len(hostBytes)+2)
	header[0] = StreamTypeDirect
	header[1] = byte(len(hostBytes))
	copy(header[2:], hostBytes)
	binary.BigEndian.PutUint16(header[2+len(hostBytes):], uint16(targetPort))

	if _, err := stream.Write(header); err != nil {
		return
	}

	pipeConns(conn, stream)
}

// HandleIncomingStream routes an incoming yamux stream on the host side.
// It reads the 1-byte stream-type prefix itself; use HandleDirectStream if the
// caller has already consumed the type byte.
func HandleIncomingStream(stream net.Conn) error {
	defer stream.Close()

	typeBuf := make([]byte, 1)
	if _, err := io.ReadFull(stream, typeBuf); err != nil {
		return err
	}

	switch typeBuf[0] {
	case StreamTypeDirect:
		return HandleDirectStream(stream)
	default:
		return fmt.Errorf("unsupported stream type: %d", typeBuf[0])
	}
}

// HandleDirectStream handles the body of a StreamTypeDirect forwarding stream.
// The type byte has already been consumed by the caller; this function reads
// the host-length, host, and port sub-header, then proxies traffic.
func HandleDirectStream(stream net.Conn) error {
	defer stream.Close()

	lenBuf := make([]byte, 1)
	if _, err := io.ReadFull(stream, lenBuf); err != nil {
		return err
	}
	hostLen := int(lenBuf[0])
	hostBuf := make([]byte, hostLen)
	if _, err := io.ReadFull(stream, hostBuf); err != nil {
		return err
	}
	portBuf := make([]byte, 2)
	if _, err := io.ReadFull(stream, portBuf); err != nil {
		return err
	}
	port := binary.BigEndian.Uint16(portBuf)

	targetAddr := fmt.Sprintf("%s:%d", string(hostBuf), port)
	targetConn, err := net.DialTimeout("tcp", targetAddr, 10*time.Second)
	if err != nil {
		return err
	}
	defer targetConn.Close()

	pipeConns(stream, targetConn)
	return nil
}

// StartSOCKS5Proxy starts a local SOCKS5 proxy server that tunnels traffic through the remote host
func (m *TunnelManager) StartSOCKS5Proxy(bindAddr string, port int) (net.Listener, error) {
	addr := fmt.Sprintf("%s:%d", bindAddr, port)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return nil, fmt.Errorf("failed to bind SOCKS5 on %s: %w", addr, err)
	}

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go m.handleSOCKS5Client(conn)
		}
	}()

	return listener, nil
}

func (m *TunnelManager) handleSOCKS5Client(conn net.Conn) {
	defer conn.Close()

	// 1. Negotiation
	header := make([]byte, 2)
	if _, err := io.ReadFull(conn, header); err != nil || header[0] != 0x05 {
		return
	}
	numMethods := int(header[1])
	methods := make([]byte, numMethods)
	if _, err := io.ReadFull(conn, methods); err != nil {
		return
	}
	// Reply: version 5, no authentication required (0x00)
	if _, err := conn.Write([]byte{0x05, 0x00}); err != nil {
		return
	}

	// 2. Request details
	req := make([]byte, 4)
	if _, err := io.ReadFull(conn, req); err != nil || req[0] != 0x05 || req[1] != 0x01 { // 0x01 is CONNECT
		_, _ = conn.Write([]byte{0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0}) // Command not supported
		return
	}

	var targetHost string
	switch req[3] {
	case 0x01: // IPv4
		ip := make([]byte, 4)
		if _, err := io.ReadFull(conn, ip); err != nil {
			return
		}
		targetHost = net.IP(ip).String()
	case 0x03: // Domain name
		lenBuf := make([]byte, 1)
		if _, err := io.ReadFull(conn, lenBuf); err != nil {
			return
		}
		domain := make([]byte, lenBuf[0])
		if _, err := io.ReadFull(conn, domain); err != nil {
			return
		}
		targetHost = string(domain)
	case 0x04: // IPv6
		ip := make([]byte, 16)
		if _, err := io.ReadFull(conn, ip); err != nil {
			return
		}
		targetHost = net.IP(ip).String()
	default:
		_, _ = conn.Write([]byte{0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0}) // Address type not supported
		return
	}

	portBuf := make([]byte, 2)
	if _, err := io.ReadFull(conn, portBuf); err != nil {
		return
	}
	targetPort := int(binary.BigEndian.Uint16(portBuf))

	// Open yamux stream to remote host
	stream, err := m.session.OpenStream(nil)
	if err != nil {
		_, _ = conn.Write([]byte{0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0}) // General failure
		return
	}
	defer stream.Close()

	// Write forward header
	hostBytes := []byte(targetHost)
	streamHeader := make([]byte, 1+1+len(hostBytes)+2)
	streamHeader[0] = StreamTypeDirect
	streamHeader[1] = byte(len(hostBytes))
	copy(streamHeader[2:], hostBytes)
	binary.BigEndian.PutUint16(streamHeader[2+len(hostBytes):], uint16(targetPort))

	if _, err := stream.Write(streamHeader); err != nil {
		_, _ = conn.Write([]byte{0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0})
		return
	}

	// SOCKS5 success reply
	if _, err := conn.Write([]byte{0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0}); err != nil {
		return
	}

	pipeConns(conn, stream)
}

func pipeConns(c1, c2 net.Conn) {
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		_, _ = io.Copy(c1, c2)
		_ = c1.Close()
	}()

	go func() {
		defer wg.Done()
		_, _ = io.Copy(c2, c1)
		_ = c2.Close()
	}()

	wg.Wait()
}

// Close terminates all active forwarding
func (m *TunnelManager) Close() error {
	m.closeMu.Lock()
	defer m.closeMu.Unlock()
	if m.isClosed {
		return nil
	}
	m.isClosed = true
	close(m.closeCh)
	return nil
}
