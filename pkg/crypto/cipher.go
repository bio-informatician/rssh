package crypto

import (
	"crypto/cipher"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"golang.org/x/crypto/chacha20poly1305"
)

const (
	MaxFrameSize = 32768 // 32 KB chunk size
	nonceSize    = chacha20poly1305.NonceSize
	overhead     = chacha20poly1305.Overhead
)

// SecureConn wraps a net.Conn with ChaCha20-Poly1305 authenticated encryption
type SecureConn struct {
	conn net.Conn

	writeAEAD     cipher.AEAD
	readAEAD      cipher.AEAD
	writeNonceSeq uint64
	readNonceSeq  uint64

	writeMu sync.Mutex
	readMu  sync.Mutex

	readBuf    []byte
	readBufOff int
	isClosed   bool
	closeMu    sync.RWMutex
}

// NewSecureConn initializes an end-to-end encrypted connection from derived session keys
func NewSecureConn(conn net.Conn, keys *SessionKeys, isHost bool) (*SecureConn, error) {
	var writeKey, readKey []byte
	if isHost {
		writeKey = keys.HostToClientKey
		readKey = keys.ClientToHostKey
	} else {
		writeKey = keys.ClientToHostKey
		readKey = keys.HostToClientKey
	}

	wAEAD, err := chacha20poly1305.New(writeKey)
	if err != nil {
		return nil, fmt.Errorf("failed to init write aead: %w", err)
	}

	rAEAD, err := chacha20poly1305.New(readKey)
	if err != nil {
		return nil, fmt.Errorf("failed to init read aead: %w", err)
	}

	return &SecureConn{
		conn:      conn,
		writeAEAD: wAEAD,
		readAEAD:  rAEAD,
	}, nil
}

// Write encrypts and sends data in frames
func (s *SecureConn) Write(b []byte) (int, error) {
	s.closeMu.RLock()
	if s.isClosed {
		s.closeMu.RUnlock()
		return 0, errors.New("secure connection closed")
	}
	s.closeMu.RUnlock()

	s.writeMu.Lock()
	defer s.writeMu.Unlock()

	totalSent := 0
	for totalSent < len(b) {
		chunkSize := len(b) - totalSent
		if chunkSize > MaxFrameSize {
			chunkSize = MaxFrameSize
		}
		chunk := b[totalSent : totalSent+chunkSize]

		nonce := make([]byte, nonceSize)
		binary.BigEndian.PutUint64(nonce[4:], s.writeNonceSeq)
		s.writeNonceSeq++

		ciphertext := s.writeAEAD.Seal(nil, nonce, chunk, nil)
		frameLen := uint32(len(ciphertext))

		lenBuf := make([]byte, 4)
		binary.BigEndian.PutUint32(lenBuf, frameLen)

		// Send frame: [4-byte length][ciphertext+tag]
		if _, err := s.conn.Write(lenBuf); err != nil {
			return totalSent, err
		}
		if _, err := s.conn.Write(ciphertext); err != nil {
			return totalSent, err
		}

		totalSent += chunkSize
	}

	return totalSent, nil
}

// Read receives and decrypts incoming frames
func (s *SecureConn) Read(b []byte) (int, error) {
	s.readMu.Lock()
	defer s.readMu.Unlock()

	// Return remaining buffered plaintext if available
	if s.readBufOff < len(s.readBuf) {
		n := copy(b, s.readBuf[s.readBufOff:])
		s.readBufOff += n
		if s.readBufOff >= len(s.readBuf) {
			s.readBuf = nil
			s.readBufOff = 0
		}
		return n, nil
	}

	// Read frame length
	lenBuf := make([]byte, 4)
	if _, err := io.ReadFull(s.conn, lenBuf); err != nil {
		return 0, err
	}
	frameLen := binary.BigEndian.Uint32(lenBuf)
	if frameLen > MaxFrameSize+overhead+1024 {
		return 0, fmt.Errorf("frame size %d exceeds safety threshold", frameLen)
	}

	// Read ciphertext
	cipherBuf := make([]byte, frameLen)
	if _, err := io.ReadFull(s.conn, cipherBuf); err != nil {
		return 0, err
	}

	// Decrypt
	nonce := make([]byte, nonceSize)
	binary.BigEndian.PutUint64(nonce[4:], s.readNonceSeq)
	s.readNonceSeq++

	plaintext, err := s.readAEAD.Open(nil, nonce, cipherBuf, nil)
	if err != nil {
		return 0, fmt.Errorf("decryption/authentication failure: %w", err)
	}

	n := copy(b, plaintext)
	if n < len(plaintext) {
		s.readBuf = plaintext
		s.readBufOff = n
	} else {
		s.readBuf = nil
		s.readBufOff = 0
	}

	return n, nil
}

// Close closes the underlying connection
func (s *SecureConn) Close() error {
	s.closeMu.Lock()
	s.isClosed = true
	s.closeMu.Unlock()
	return s.conn.Close()
}

// LocalAddr returns the local network address
func (s *SecureConn) LocalAddr() net.Addr {
	return s.conn.LocalAddr()
}

// RemoteAddr returns the remote network address
func (s *SecureConn) RemoteAddr() net.Addr {
	return s.conn.RemoteAddr()
}

// SetDeadline sets the read and write deadlines
func (s *SecureConn) SetDeadline(t time.Time) error {
	return s.conn.SetDeadline(t)
}

// SetReadDeadline sets the deadline for future Read calls
func (s *SecureConn) SetReadDeadline(t time.Time) error {
	return s.conn.SetReadDeadline(t)
}

// SetWriteDeadline sets the deadline for future Write calls
func (s *SecureConn) SetWriteDeadline(t time.Time) error {
	return s.conn.SetWriteDeadline(t)
}
