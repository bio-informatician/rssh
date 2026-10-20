// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package p2p

import (
	"context"
	"testing"
	"time"
)

func TestWebRTCP2PDataChannel(t *testing.T) {
	var peerA, peerB *Peer
	var err error

	peerA, err = NewPeer(true, func(signalJSON string) {
		if peerB != nil {
			go func() {
				_ = peerB.HandleSignal(signalJSON)
			}()
		}
	})
	if err != nil {
		t.Fatalf("failed to create peer A: %v", err)
	}
	defer peerA.Close()

	peerB, err = NewPeer(false, func(signalJSON string) {
		if peerA != nil {
			go func() {
				_ = peerA.HandleSignal(signalJSON)
			}()
		}
	})
	if err != nil {
		t.Fatalf("failed to create peer B: %v", err)
	}
	defer peerB.Close()

	// Peer A initiates offer
	if err := peerA.CreateOffer(); err != nil {
		t.Fatalf("failed to create offer: %v", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	type res struct {
		conn *DataChannelConn
		err  error
	}

	resACh := make(chan res, 1)
	resBCh := make(chan res, 1)

	go func() {
		c, err := peerA.WaitReady(ctx)
		resACh <- res{conn: c, err: err}
	}()

	go func() {
		c, err := peerB.WaitReady(ctx)
		resBCh <- res{conn: c, err: err}
	}()

	resA := <-resACh
	if resA.err != nil {
		t.Fatalf("peer A failed to establish data channel: %v", resA.err)
	}
	defer resA.conn.Close()

	resB := <-resBCh
	if resB.err != nil {
		t.Fatalf("peer B failed to establish data channel: %v", resB.err)
	}
	defer resB.conn.Close()

	// Test writing from Peer A to Peer B
	msgA := []byte("Hello P2P from Peer A!")
	go func() {
		if _, err := resA.conn.Write(msgA); err != nil {
			t.Errorf("peer A write failed: %v", err)
		}
	}()

	bufB := make([]byte, 128)
	n, err := resB.conn.Read(bufB)
	if err != nil {
		t.Fatalf("peer B read failed: %v", err)
	}
	if string(bufB[:n]) != string(msgA) {
		t.Fatalf("expected '%s', got '%s'", msgA, bufB[:n])
	}

	// Test writing from Peer B to Peer A
	msgB := []byte("Hello P2P from Peer B!")
	go func() {
		if _, err := resB.conn.Write(msgB); err != nil {
			t.Errorf("peer B write failed: %v", err)
		}
	}()

	bufA := make([]byte, 128)
	n, err = resA.conn.Read(bufA)
	if err != nil {
		t.Fatalf("peer A read failed: %v", err)
	}
	if string(bufA[:n]) != string(msgB) {
		t.Fatalf("expected '%s', got '%s'", msgB, bufA[:n])
	}
}
