package signaling

import (
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

// NewRateLimiter creates a sliding window rate limiter
func NewRateLimiter(maxRequests int, window time.Duration) *RateLimiter {
	return &RateLimiter{
		maxRequests: maxRequests,
		window:      window,
		clients:     make(map[string][]time.Time),
	}
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

// CleanStale removes inactive client entries
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
