package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrOwnerLocked is returned when a property owner tries to chat/call a tenant
// before they have received even one visit request.
var ErrOwnerLocked = errors.New("chat and call unlock once you receive your first visit request")

// ContactAllowed reports whether `sender` may chat/call `other`.
//
//   - Tenant (buyer) side is never locked: a tenant can always chat/call the
//     owner, before or after any visit.
//   - Owner side is locked until the owner has received at least one visit
//     request (any status) on any of their properties.
func ContactAllowed(ctx context.Context, db *pgxpool.Pool, sender, other string) (bool, error) {
	var buyerSide, ownerSide, otherIsOwner bool
	err := db.QueryRow(ctx, `
		SELECT
		  -- sender is the tenant: enquired with / booked a visit with `other`
		  (EXISTS (SELECT 1 FROM leads l WHERE l.buyer_id = $1::uuid AND l.owner_id = $2::uuid)
		   OR EXISTS (SELECT 1 FROM visits v JOIN properties p ON p.id = v.property_id
		              WHERE v.visitor_id = $1::uuid AND p.owner_id = $2::uuid)),
		  -- sender is the owner: `other` enquired / booked a visit on their property
		  (EXISTS (SELECT 1 FROM leads l WHERE l.owner_id = $1::uuid AND l.buyer_id = $2::uuid)
		   OR EXISTS (SELECT 1 FROM visits v JOIN properties p ON p.id = v.property_id
		              WHERE p.owner_id = $1::uuid AND v.visitor_id = $2::uuid)),
		  -- `other` owns at least one property (fresh "Contact Owner" tap)
		  EXISTS (SELECT 1 FROM properties p WHERE p.owner_id = $2::uuid)`,
		sender, other).Scan(&buyerSide, &ownerSide, &otherIsOwner)
	if err != nil {
		return false, err
	}

	// Tenant side: always open.
	if buyerSide {
		return true, nil
	}
	// Owner side: open only after the first visit request arrives.
	if ownerSide {
		var gotRequest bool
		err := db.QueryRow(ctx, `
			SELECT EXISTS (
				SELECT 1 FROM visits v
				JOIN properties p ON p.id = v.property_id
				WHERE p.owner_id = $1::uuid
			)`, sender).Scan(&gotRequest)
		return gotRequest, err
	}
	// No history yet: a tenant contacting a property owner is always allowed.
	return otherIsOwner, nil
}