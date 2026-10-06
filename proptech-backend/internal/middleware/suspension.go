package middleware

import (
	"context"
	"sync"
	"time"
)

type suspEntry struct {
	suspended bool
	expires   time.Time
}

var (
	suspendedCheck func(ctx context.Context, userID string) bool
	suspCache      sync.Map // userID -> suspEntry
)

const suspCacheTTL = 20 * time.Second

// SetSuspensionChecker is called once from main with a DB-backed lookup.
func SetSuspensionChecker(f func(ctx context.Context, userID string) bool) { suspendedCheck = f }

// InvalidateSuspension drops the cached answer for a user (after suspend/unsuspend).
func InvalidateSuspension(userID string) { suspCache.Delete(userID) }

func isSuspended(ctx context.Context, userID string) bool {
	if suspendedCheck == nil || userID == "" || userID == AdminUserID {
		return false
	}
	if v, ok := suspCache.Load(userID); ok {
		e := v.(suspEntry)
		if time.Now().Before(e.expires) {
			return e.suspended
		}
	}
	s := suspendedCheck(ctx, userID)
	suspCache.Store(userID, suspEntry{suspended: s, expires: time.Now().Add(suspCacheTTL)})
	return s
}