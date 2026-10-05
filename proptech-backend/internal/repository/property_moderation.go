package repository

import (
	"context"
	"fmt"
	"strings"

	"proptech-backend/internal/models"
)

const (
	ApprovalPending  = "pending"
	ApprovalApproved = "approved"
	ApprovalRejected = "rejected"
)

// ModerationInfo is the approval state of one listing.
type ModerationInfo struct {
	OwnerID *string
	Status  string
	Reason  string
}

// CanView: approved listings are public; pending/rejected ones are visible
// only to their owner.
func (m ModerationInfo) CanView(viewerID string) bool {
	if m.Status == ApprovalApproved {
		return true
	}
	return viewerID != "" && m.OwnerID != nil && *m.OwnerID == viewerID
}

func (r *PropertyRepository) ModerationInfo(ctx context.Context, id string) (*ModerationInfo, error) {
	var m ModerationInfo
	err := r.db.QueryRow(ctx,
		`SELECT owner_id::text, approval_status, rejection_reason FROM properties WHERE id = $1::uuid`, id,
	).Scan(&m.OwnerID, &m.Status, &m.Reason)
	if err != nil {
		return nil, err
	}
	return &m, nil
}

// SearchVisible is Search() limited to what the viewer may see: approved
// listings, plus the viewer's own pending/rejected ones (so My Properties
// still shows them). viewerID is "" for anonymous callers.
func (r *PropertyRepository) SearchVisible(ctx context.Context, f models.PropertyFilter, viewerID string) ([]models.Property, int, error) {
	where, args, orderBy := BuildPropertySearch(f)

	cond := "approval_status = 'approved'"
	if viewerID != "" {
		args = append(args, viewerID)
		cond = fmt.Sprintf("(approval_status = 'approved' OR owner_id = $%d::uuid)", len(args))
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

// ResubmitIfRejected puts a rejected listing back in the review queue after
// its owner edits it. Returns true when the status actually changed.
func (r *PropertyRepository) ResubmitIfRejected(ctx context.Context, id string) (bool, error) {
	tag, err := r.db.Exec(ctx, `
		UPDATE properties
		SET approval_status = 'pending', rejection_reason = '', reviewed_at = NULL
		WHERE id = $1::uuid AND approval_status = 'rejected'`, id)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

func (r *PropertyRepository) SetDuplicateOf(ctx context.Context, id, duplicateOf string) error {
	_, err := r.db.Exec(ctx, `UPDATE properties SET duplicate_of = $2::uuid WHERE id = $1::uuid`, id, duplicateOf)
	return err
}

// ---- duplicate detection ---------------------------------------------------

// DupQuery is what we compare a new listing against.
type DupQuery struct {
	Category, BHK, Society, Locality, City, Pincode string
	Area                                            float64
	Floor                                           int
	Lat, Lng                                        float64
	ExcludeID                                       string // listing being edited, if any
}

type DuplicateMatch struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	ImageURL  string  `json:"image_url"`
	Location  string  `json:"location"`
	Price     float64 `json:"price"`
	Status    string  `json:"approval_status"`
	SameOwner bool    `json:"same_owner"`
}

// FindDuplicates returns up to 5 existing (non-rejected) listings that look
// like the same property: same city, category, BHK and floor, area within 5%,
// AND the same society, OR within ~50 m, OR (no society) same pincode+locality.
func (r *PropertyRepository) FindDuplicates(ctx context.Context, q DupQuery, ownerID string) ([]DuplicateMatch, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id::text, title, image_url, location, price::float8,
		       approval_status, COALESCE(owner_id::text, '')
		FROM properties
		WHERE approval_status <> 'rejected'
		  AND LOWER(category) = LOWER($1)
		  AND LOWER(bhk) = LOWER($2)
		  AND floor_number = $3
		  AND ($4::float8 <= 0 OR area_sqft = 0 OR area_sqft BETWEEN $4::float8 * 0.95 AND $4::float8 * 1.05)
		  AND LOWER(BTRIM(city)) = LOWER(BTRIM($5))
		  AND (
		        (BTRIM($6) <> '' AND LOWER(BTRIM(society)) = LOWER(BTRIM($6)))
		     OR ($7::float8 <> 0 AND $8::float8 <> 0 AND latitude <> 0
		         AND ABS(latitude - $7::float8) < 0.0005 AND ABS(longitude - $8::float8) < 0.0005)
		     OR (BTRIM($6) = '' AND BTRIM($9) <> '' AND pincode = BTRIM($9)
		         AND LOWER(BTRIM(locality)) = LOWER(BTRIM($10)))
		  )
		  AND ($11 = '' OR id::text <> $11)
		ORDER BY created_at DESC
		LIMIT 5`,
		strings.TrimSpace(q.Category), strings.TrimSpace(q.BHK), q.Floor, q.Area, q.City,
		q.Society, q.Lat, q.Lng, q.Pincode, q.Locality, q.ExcludeID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []DuplicateMatch{}
	for rows.Next() {
		var m DuplicateMatch
		var owner string
		if err := rows.Scan(&m.ID, &m.Title, &m.ImageURL, &m.Location, &m.Price, &m.Status, &owner); err != nil {
			return nil, err
		}
		m.SameOwner = ownerID != "" && owner == ownerID
		out = append(out, m)
	}
	return out, rows.Err()
}

// GetByOwnerIDVisible is GetByOwnerID for public viewing: other people see
// only approved listings, the owner sees all of their own.
func (r *PropertyRepository) GetByOwnerIDVisible(ctx context.Context, ownerID, viewerID string) ([]models.Property, error) {
	rows, err := r.db.Query(ctx, `
		SELECT `+propertyColumns+`
		FROM properties
		WHERE owner_id = $1::uuid
		  AND (approval_status = 'approved' OR owner_id::text = $2)
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