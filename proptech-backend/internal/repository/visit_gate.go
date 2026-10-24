package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrOwnerLocked is kept only so existing references compile. Chat/call are
// no longer locked for anyone, so it is never returned.
var ErrOwnerLocked = errors.New("chat and call are not available")

// ContactAllowed: chat/call is open for everyone (tenant and owner), always.
func ContactAllowed(ctx context.Context, db *pgxpool.Pool, sender, other string) (bool, error) {
	return true, nil
}