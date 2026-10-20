// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package p2p

import (
	"errors"
	"io"
	"net"
	"sync"
	"time"

	"github.com/pion/webrtc/v4"
)

const maxWebRTCChunkSize = 16384 // 16KB WebRTC DataChannel chunk

// DataChannelConn wraps a WebRTC DataChannel to implement net.Conn
type DataChannelConn struct {
	dc *webrtc.DataChannel
	pc *webrtc.PeerConnection

	readCh   chan []byte
	readBuf  []byte
	isClosed bool
	closeCh  chan struct{}
	closeMu  sync.RWMutex
}

// NewDataChannelConn creates a net.Conn over an open WebRTC DataChannel
func NewDataChannelConn(pc *webrtc.PeerConnection, dc *webrtc.DataChannel) *DataChannelConn {
	conn := &DataChannelConn{
		dc:      dc,
		pc:      pc,
		readCh:  make(chan []byte, 1024),
		closeCh: make(chan struct{}),
	}

	dc.OnMessage(func(msg webrtc.DataChannelMessage) {
		conn.closeMu.RLock()
		defer conn.closeMu.RUnlock()
		if conn.isClosed {
			return
		}

		data := make([]byte, len(msg.Data))
		copy(data, msg.Data)

		select {
		case conn.readCh <- data:
		case <-conn.closeCh:
		}
	})

	dc.OnClose(func() {
		_ = conn.Close()
	})

	return conn
}

func (c *DataChannelConn) Read(b []byte) (int, error) {
	if len(c.readBuf) > 0 {
		n := copy(b, c.readBuf)
		c.readBuf = c.readBuf[n:]
		return n, nil
	}

	select {
	case <-c.closeCh:
		return 0, io.EOF
	case data, ok := <-c.readCh:
		if !ok {
			return 0, io.EOF
		}
		n := copy(b, data)
		if n < len(data) {
			c.readBuf = data[n:]
		}
		return n, nil
	}
}

func (c *DataChannelConn) Write(b []byte) (int, error) {
	c.closeMu.RLock()
	if c.isClosed {
		c.closeMu.RUnlock()
		return 0, errors.New("data channel conn closed")
	}
	c.closeMu.RUnlock()

	totalSent := 0
	for totalSent < len(b) {
		chunkSize := len(b) - totalSent
		if chunkSize > maxWebRTCChunkSize {
			chunkSize = maxWebRTCChunkSize
		}
		chunk := b[totalSent : totalSent+chunkSize]

		if err := c.dc.Send(chunk); err != nil {
			return totalSent, err
		}
		totalSent += chunkSize
	}

	return totalSent, nil
}

func (c *DataChannelConn) Close() error {
	c.closeMu.Lock()
	if c.isClosed {
		c.closeMu.Unlock()
		return nil
	}
	c.isClosed = true
	close(c.closeCh)
	c.closeMu.Unlock()

	if c.dc != nil {
		_ = c.dc.Close()
	}
	if c.pc != nil {
		_ = c.pc.Close()
	}
	return nil
}

func (c *DataChannelConn) LocalAddr() net.Addr {
	return &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: 0}
}

func (c *DataChannelConn) RemoteAddr() net.Addr {
	return &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: 0}
}

func (c *DataChannelConn) SetDeadline(t time.Time) error      { return nil }
func (c *DataChannelConn) SetReadDeadline(t time.Time) error  { return nil }
func (c *DataChannelConn) SetWriteDeadline(t time.Time) error { return nil }
