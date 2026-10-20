// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package sshserver

import (
	"errors"
	"net"
	"sync"
)

// VirtualListener provides a net.Listener backed by an internal channel
type VirtualListener struct {
	connCh   chan net.Conn
	closeCh  chan struct{}
	closeMu  sync.Mutex
	isClosed bool
}

// NewVirtualListener creates a new virtual listener
func NewVirtualListener() *VirtualListener {
	return &VirtualListener{
		connCh:  make(chan net.Conn, 128),
		closeCh: make(chan struct{}),
	}
}

// Push adds an accepted stream to the listener
func (l *VirtualListener) Push(conn net.Conn) error {
	l.closeMu.Lock()
	defer l.closeMu.Unlock()
	if l.isClosed {
		return errors.New("listener closed")
	}

	select {
	case l.connCh <- conn:
		return nil
	default:
		return errors.New("virtual listener backlog full")
	}
}

// Accept returns the next connection from the queue
func (l *VirtualListener) Accept() (net.Conn, error) {
	select {
	case <-l.closeCh:
		return nil, errors.New("virtual listener closed")
	case conn, ok := <-l.connCh:
		if !ok {
			return nil, errors.New("virtual listener closed")
		}
		return conn, nil
	}
}

// Close closes the virtual listener
func (l *VirtualListener) Close() error {
	l.closeMu.Lock()
	defer l.closeMu.Unlock()
	if l.isClosed {
		return nil
	}
	l.isClosed = true
	close(l.closeCh)
	return nil
}

// Addr returns a dummy network address
func (l *VirtualListener) Addr() net.Addr {
	return &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: 2222}
}
