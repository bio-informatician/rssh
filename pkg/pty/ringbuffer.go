// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package pty

import (
	"sync"
)

// RingBuffer is a thread-safe circular buffer for storing terminal scrollback
type RingBuffer struct {
	buf   []byte
	size  int
	start int
	count int
	mu    sync.RWMutex
}

// NewRingBuffer allocates a ring buffer of the given capacity
func NewRingBuffer(size int) *RingBuffer {
	if size <= 0 {
		size = 1024 * 1024 // 1 MB default
	}
	return &RingBuffer{
		buf:  make([]byte, size),
		size: size,
	}
}

// Write appends data to the ring buffer, overwriting older data if full
func (r *RingBuffer) Write(p []byte) (n int, err error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	for _, b := range p {
		pos := (r.start + r.count) % r.size
		r.buf[pos] = b
		if r.count < r.size {
			r.count++
		} else {
			r.start = (r.start + 1) % r.size
		}
	}
	return len(p), nil
}

// Bytes returns a copy of all current buffer contents in chronological order
func (r *RingBuffer) Bytes() []byte {
	r.mu.RLock()
	defer r.mu.RUnlock()

	res := make([]byte, r.count)
	for i := 0; i < r.count; i++ {
		res[i] = r.buf[(r.start+i)%r.size]
	}
	return res
}

// Len returns current number of bytes stored
func (r *RingBuffer) Len() int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.count
}

// Reset clears the buffer
func (r *RingBuffer) Reset() {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.start = 0
	r.count = 0
}
