// Package ratelimit counts attempts in Postgres and blocks a key temporarily
// when it goes over the limit. Works across several server instances.
package ratelimit

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/jackc/pgx/v5/pgxpool"
)

var db *pgxpool.Pool

// SetDefault is called once from main.
func SetDefault(pool *pgxpool.Pool) { db = pool }

const hitSQL = `
INSERT INTO rate_limits AS r (key, count, window_start, blocked_until)
VALUES ($1, 1, NOW(), NULL)
ON CONFLICT (key) DO UPDATE SET
  count = CASE
    WHEN r.blocked_until IS NOT NULL AND r.blocked_until > NOW() THEN r.count
    WHEN (r.blocked_until IS NOT NULL AND r.blocked_until <= NOW())
      OR r.window_start < NOW() - make_interval(secs => $2::float8) THEN 1
    ELSE r.count + 1 END,
  window_start = CASE
    WHEN r.blocked_until IS NOT NULL AND r.blocked_until > NOW() THEN r.window_start
    WHEN (r.blocked_until IS NOT NULL AND r.blocked_until <= NOW())
      OR r.window_start < NOW() - make_interval(secs => $2::float8) THEN NOW()
    ELSE r.window_start END,
  blocked_until = CASE
    WHEN r.blocked_until IS NOT NULL AND r.blocked_until > NOW() THEN r.blocked_until
    WHEN (CASE
            WHEN (r.blocked_until IS NOT NULL AND r.blocked_until <= NOW())
              OR r.window_start < NOW() - make_interval(secs => $2::float8) THEN 1
            ELSE r.count + 1 END) > $3::int
      THEN NOW() + make_interval(secs => $4::float8)
    ELSE NULL END
RETURNING (blocked_until IS NOT NULL AND blocked_until > NOW()),
          GREATEST(COALESCE(CEIL(EXTRACT(EPOCH FROM (blocked_until - NOW()))), 0), 0)::int`

// Hit records one attempt for key. More than max attempts inside window
// blocks the key for block. Returns (blocked, seconds until unblocked).
// If the database is unavailable it lets the request through.
func Hit(ctx context.Context, key string, max int, window, block time.Duration) (bool, int) {
	if db == nil {
		return false, 0
	}
	var blocked bool
	var retry int
	err := db.QueryRow(ctx, hitSQL, key, window.Seconds(), max, block.Seconds()).Scan(&blocked, &retry)
	if err != nil {
		log.Printf("ratelimit: %v", err)
		return false, 0
	}
	return blocked, retry
}

// Reject writes the standard 429 answer.
func Reject(c *gin.Context, retryAfter int) {
	if retryAfter < 1 {
		retryAfter = 1
	}
	c.Header("Retry-After", fmt.Sprint(retryAfter))
	c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
		"error":               fmt.Sprintf("Too many attempts. Please try again in %d minute(s).", (retryAfter+59)/60),
		"code":                "rate_limited",
		"retry_after_seconds": retryAfter,
	})
}

// IP limits by client IP.
func IP(name string, max int, window, block time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		if blocked, retry := Hit(c.Request.Context(), name+":ip:"+c.ClientIP(), max, window, block); blocked {
			Reject(c, retry)
			return
		}
		c.Next()
	}
}

// User limits by logged-in user (falls back to IP). Put it after AuthRequired.
func User(name string, max int, window, block time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		who := c.ClientIP()
		if v, ok := c.Get("user_id"); ok {
			if s, ok := v.(string); ok && s != "" {
				who = s
			}
		}
		if blocked, retry := Hit(c.Request.Context(), name+":user:"+who, max, window, block); blocked {
			Reject(c, retry)
			return
		}
		c.Next()
	}
}