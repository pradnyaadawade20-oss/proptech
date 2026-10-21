package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrVisitNotAccepted is returned when a buyer tries to chat/call before the
// property owner has accepted (confirmed) their visit request.
var ErrVisitNotAccepted = errors.New("chat and call unlock once the owner accepts your visit request")

// ContactAllowed reports whether `sender` may chat/call `other`.
//
//   - Owner side is never locked: a property owner can always contact a buyer
//     who has enquired (lead) or booked a visit on one of their properties.
//   - Buyer side is locked until the owner accepts: a buyer can contact the
//     owner only once a visit with that owner is confirmed/completed.
func ContactAllowed(ctx context.Context, db *pgxpool.Pool, sender, other string) (bool, error) {
	var ok bool
	err := db.QueryRow(ctx, `
		SELECT EXISTS (
			-- sender is the owner and the other person enquired on their property
			SELECT 1 FROM leads l
			WHERE l.owner_id = $1::uuid AND l.buyer_id = $2::uuid
			UNION ALL
			-- sender is the owner and the other person booked a visit on their property
			SELECT 1 FROM visits v
			JOIN properties p ON p.id = v.property_id
			WHERE p.owner_id = $1::uuid AND v.visitor_id = $2::uuid
			UNION ALL
			-- sender is the buyer and the owner accepted their visit request
			SELECT 1 FROM visits v
			JOIN properties p ON p.id = v.property_id
			WHERE v.visitor_id = $1::uuid AND p.owner_id = $2::uuid
			  AND v.status IN ('confirmed','completed')
		)`, sender, other).Scan(&ok)
	return ok, err
}