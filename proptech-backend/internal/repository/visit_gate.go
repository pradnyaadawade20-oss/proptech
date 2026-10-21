package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrVisitNotAccepted is returned when chat/call is attempted before the
// property owner has accepted (confirmed) a visit request from that buyer.
var ErrVisitNotAccepted = errors.New("chat and call unlock once the owner accepts your visit request")

// VisitAccepted reports whether a confirmed/completed visit exists between
// the two users (in either direction: buyer <-> property owner).
func VisitAccepted(ctx context.Context, db *pgxpool.Pool, a, b string) (bool, error) {
	var ok bool
	err := db.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM visits v
			JOIN properties p ON p.id = v.property_id
			WHERE v.status IN ('confirmed','completed')
			  AND ((v.visitor_id = $1::uuid AND p.owner_id = $2::uuid)
			    OR (v.visitor_id = $2::uuid AND p.owner_id = $1::uuid))
		)`, a, b).Scan(&ok)
	return ok, err
}