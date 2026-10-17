package repository

import (
	"context"
	"fmt"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
)

// PublicCondition = a listing anyone may see: the owner approved it (broker listings) AND an admin
// has not hidden or rejected it. Listings still 'pending' admin review stay visible as before.
const PublicCondition = LiveCondition + ` AND approval_status NOT IN ('hidden', 'rejected')`

// SearchForViewer is Search() limited to what this viewer may see: every live listing, plus
// the viewer's own listings (so a broker still sees the ones waiting for owner approval).
// viewerID is "" for anonymous callers.
func (r *PropertyRepository) SearchForViewer(ctx context.Context, f models.PropertyFilter, viewerID string) ([]models.Property, int, error) {
	where, args, orderBy := BuildPropertySearch(f)

	cond := "(" + PublicCondition + ")"
	if viewerID != "" {
		args = append(args, viewerID)
		cond = fmt.Sprintf("((%s) OR owner_id = $%d::uuid)", PublicCondition, len(args))
	}
	if where == "" {
		where = "WHERE " + cond
	} else {
		where += " AND " + cond
	}

	var total int
	if err := r.db.QueryRow(ctx, "SELECT COUNT(*) FROM properties "+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	query := "SELECT " + propertyColumns + " FROM properties " + where + " " + orderBy
	if f.Limit > 0 {
		limit := f.Limit
		if limit > maxPageSize {
			limit = maxPageSize
		}
		page := f.Page
		if page < 1 {
			page = 1
		}
		args = append(args, limit, (page-1)*limit)
		query += fmt.Sprintf(" LIMIT $%d OFFSET $%d", len(args)-1, len(args))
	}

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	properties := []models.Property{}
	for rows.Next() {
		var p models.Property
		if err := rows.Scan(propertyDests(&p)...); err != nil {
			return nil, 0, err
		}
		properties = append(properties, p)
	}
	return properties, total, rows.Err()
}

// GetByIDForViewer returns pgx.ErrNoRows for a listing that is not public (waiting for the owner,
// hidden or rejected) unless the viewer is the account that posted it.
func (r *PropertyRepository) GetByIDForViewer(ctx context.Context, id, viewerID string) (*models.Property, error) {
	p, err := r.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if p.OwnerID != nil && viewerID != "" && *p.OwnerID == viewerID {
		return p, nil // owners always see their own listings (pending, hidden, rejected)
	}
	var public bool
	if err := r.db.QueryRow(ctx,
		`SELECT `+PublicCondition+` FROM properties WHERE id = $1::uuid`, id).Scan(&public); err != nil {
		return nil, err
	}
	if !public {
		return nil, pgx.ErrNoRows
	}
	return p, nil
}

// GetByOwnerIDForViewer lists one account's listings: everyone sees the live ones,
// the account itself also sees the ones still waiting for owner approval.
func (r *PropertyRepository) GetByOwnerIDForViewer(ctx context.Context, ownerID, viewerID string) ([]models.Property, error) {
	rows, err := r.db.Query(ctx, `
		SELECT `+propertyColumns+`
		FROM properties
		WHERE owner_id = $1::uuid
		  AND ((`+PublicCondition+`) OR owner_id::text = $2)
		ORDER BY created_at DESC`, ownerID, viewerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	properties := []models.Property{}
	for rows.Next() {
		var p models.Property
		if err := rows.Scan(propertyDests(&p)...); err != nil {
			return nil, err
		}
		properties = append(properties, p)
	}
	return properties, rows.Err()
}