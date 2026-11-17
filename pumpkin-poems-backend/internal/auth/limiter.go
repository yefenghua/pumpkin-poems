package auth

import (
	"sync"
	"time"
)

// LoginLimiter slows online password guessing: after MaxFailures failed
// logins for one account ID within Window, further attempts on that account
// are refused until the window has passed. It is in-memory, which is enough
// for the single-binary deployment (Argon2id already makes each guess slow).
type LoginLimiter struct {
	MaxFailures int
	Window      time.Duration
	Now         func() time.Time

	mu       sync.Mutex
	failures map[string][]time.Time
	lastGC   time.Time
}

func NewLoginLimiter() *LoginLimiter {
	return &LoginLimiter{MaxFailures: 10, Window: 15 * time.Minute, Now: time.Now, failures: map[string][]time.Time{}}
}

// Allow reports whether a login attempt for accountID may proceed, and if not,
// how long until it may.
func (l *LoginLimiter) Allow(accountID string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.Now()
	l.gc(now)
	recent := l.prune(accountID, now)
	if len(recent) < l.MaxFailures {
		return true, 0
	}
	return false, recent[0].Add(l.Window).Sub(now)
}

// Fail records a failed attempt.
func (l *LoginLimiter) Fail(accountID string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.Now()
	l.failures[accountID] = append(l.prune(accountID, now), now)
}

// Reset forgets failures after a successful login.
func (l *LoginLimiter) Reset(accountID string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.failures, accountID)
}

func (l *LoginLimiter) prune(accountID string, now time.Time) []time.Time {
	ts := l.failures[accountID]
	cut := now.Add(-l.Window)
	i := 0
	for i < len(ts) && !ts[i].After(cut) {
		i++
	}
	ts = ts[i:]
	if len(ts) == 0 {
		delete(l.failures, accountID)
	} else {
		l.failures[accountID] = ts
	}
	return ts
}

// gc drops stale accounts once per window so the map cannot grow without bound.
func (l *LoginLimiter) gc(now time.Time) {
	if now.Sub(l.lastGC) < l.Window {
		return
	}
	l.lastGC = now
	for id := range l.failures {
		l.prune(id, now)
	}
}
