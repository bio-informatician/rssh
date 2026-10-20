// Copyright (C) 2026 Rakhssh Contributors - AGPLv3
package signaling

import (
	"net"
	"net/http"
	"sync"
	"time"
)

// RateLimiter enforces request rate limits per client IP address
type RateLimiter struct {
	maxRequests int
	window      time.Duration
	clients     map[string][]time.Time
	mu          sync.Mutex
}

// NewRateLimiter creates a sliding window rate limiter and starts a background stale-entry cleanup goroutine.
func NewRateLimiter(maxRequests int, window time.Duration) *RateLimiter {
	r := &RateLimiter{
		maxRequests: maxRequests,
		window:      window,
		clients:     make(map[string][]time.Time),
	}
	go r.periodicCleanup()
	return r
}

// Allow checks if the given key is allowed to make a request
func (r *RateLimiter) Allow(key string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-r.window)

	timestamps := r.clients[key]
	valid := make([]time.Time, 0, len(timestamps))
	for _, t := range timestamps {
		if t.After(cutoff) {
			valid = append(valid, t)
		}
	}

	if len(valid) >= r.maxRequests {
		r.clients[key] = valid
		return false
	}

	valid = append(valid, now)
	r.clients[key] = valid
	return true
}

// CleanStale removes inactive client entries (also called periodically).
func (r *RateLimiter) CleanStale() {
	r.mu.Lock()
	defer r.mu.Unlock()

	now := time.Now()
	cutoff := now.Add(-r.window)

	for key, timestamps := range r.clients {
		if len(timestamps) == 0 || timestamps[len(timestamps)-1].Before(cutoff) {
			delete(r.clients, key)
		}
	}
}

// periodicCleanup runs CleanStale every window period in the background.
func (r *RateLimiter) periodicCleanup() {
	ticker := time.NewTicker(r.window)
	defer ticker.Stop()
	for range ticker.C {
		r.CleanStale()
	}
}

// ExtractIP parses the IP from an "ip:port" or raw IP RemoteAddr string,
// stripping the port so rate-limiting is per-IP rather than per-socket.
// A new WebSocket from the same IP should not reset the rate limit counter.
func ExtractIP(remoteAddr string) string {
	// net.SplitHostPort would be ideal but imports net; do it inline
	for i := len(remoteAddr) - 1; i >= 0; i-- {
		if remoteAddr[i] == ':' {
			candidate := remoteAddr[:i]
			// IPv6 addresses wrapped in brackets, e.g. [::1]:1234
			if len(candidate) >= 2 && candidate[0] == '[' && candidate[len(candidate)-1] == ']' {
				return candidate[1 : len(candidate)-1]
			}
			// Plain IPv4 or IPv6 without brackets
			return candidate
		}
	}
	return remoteAddr
}

// isTrustedProxy returns true if the incoming IP is loopback or a private subnet (Docker bridge/LAN)
func isTrustedProxy(ipStr string) bool {
	if ipStr == "127.0.0.1" || ipStr == "::1" {
		return true
	}
	parsed := net.ParseIP(ipStr)
	if parsed == nil {
		return false
	}
	return parsed.IsLoopback() || parsed.IsPrivate()
}

// RealIPFromRequest extracts the true client IP, honouring X-Real-IP / X-Forwarded-For
// if the connection comes from localhost or a trusted private proxy (Docker bridge gateway, LAN).
func RealIPFromRequest(r *http.Request) string {
	remoteIP := ExtractIP(r.RemoteAddr)
	if isTrustedProxy(remoteIP) {
		// Prefer X-Real-IP set explicitly by reverse proxy (cannot be spoofed by client append)
		if xri := r.Header.Get("X-Real-IP"); xri != "" {
			trimmed := trimSpace(xri)
			if trimmed != "" {
				return trimmed
			}
		}
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			for _, part := range splitCSV(xff) {
				if ip := trimSpace(part); ip != "" {
					return ip
				}
			}
		}
	}
	return remoteIP
}

func splitCSV(s string) []string {
	var out []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == ',' {
			out = append(out, s[start:i])
			start = i + 1
		}
	}
	return append(out, s[start:])
}

func trimSpace(s string) string {
	i := 0
	for i < len(s) && (s[i] == ' ' || s[i] == '\t') {
		i++
	}
	j := len(s)
	for j > i && (s[j-1] == ' ' || s[j-1] == '\t') {
		j--
	}
	return s[i:j]
}
