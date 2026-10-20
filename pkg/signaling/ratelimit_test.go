// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package signaling

import (
	"testing"
	"time"
)

func TestRateLimiter(t *testing.T) {
	rl := NewRateLimiter(3, 100*time.Millisecond)

	ip := "192.168.1.100"

	// First 3 requests should be allowed
	if !rl.Allow(ip) || !rl.Allow(ip) || !rl.Allow(ip) {
		t.Fatal("first 3 requests should be allowed")
	}

	// 4th request within window must be rejected
	if rl.Allow(ip) {
		t.Fatal("4th request should be rejected by rate limiter")
	}

	// Wait for window to expire
	time.Sleep(120 * time.Millisecond)

	// Should be allowed again
	if !rl.Allow(ip) {
		t.Fatal("request after window expiration should be allowed")
	}
}
