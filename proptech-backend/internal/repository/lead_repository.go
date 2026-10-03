package repository

import (
	"context"
	"errors"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type LeadRepository struct {
	db *pgxpool.Pool
}

func NewLeadRepository(db *pgxpool.Pool) *LeadRepository {
	return &LeadRepository{db: db}
}

const leadSelect = `
	SELECT l.id, l.property_id, p.title, p.image_url, l.owner_id, l.buyer_id,
	       l.name, l.phone, COALESCE(u.email, ''), l.message, l.source, l.status, l.created_at, l.updated_at
	FROM leads l
	JOIN properties p ON p.id = l.property_id
	JOIN users u ON u.id = l.buyer_id
`

func scanLead(row interface{ Scan(dest ...any) error }) (*models.Lead, error) {
	var l models.Lead
	err := row.Scan(&l.ID, &l.PropertyID, &l.PropertyTitle, &l.PropertyImageURL, &l.OwnerID, &l.BuyerID,
		&l.Name, &l.Phone, &l.Email, &l.Message, &l.Source, &l.Status, &l.CreatedAt, &l.UpdatedAt)
	if err != nil {
		return nil, err
	}
	return &l, nil
}

// Upsert creates the lead, or refreshes it if this buyer already enquired
// about this property (no duplicates). isNew tells the caller whether to
// notify the owner. A repeat enquiry on a closed lead re-opens it as "new".
func (r *LeadRepository) Upsert(ctx context.Context, ownerID, buyerID string, req models.CreateLeadRequest) (lead *models.Lead, isNew bool, err error) {
	var id string
	err = r.db.QueryRow(ctx, `
		INSERT INTO leads (property_id, owner_id, buyer_id, name, phone, message, source)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (property_id, buyer_id) DO UPDATE SET
			name       = CASE WHEN EXCLUDED.name  <> '' THEN EXCLUDED.name  ELSE leads.name  END,
			phone      = CASE WHEN EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE leads.phone END,
			message    = CASE WHEN EXCLUDED.message <> '' THEN EXCLUDED.message ELSE leads.message END,
			status     = CASE WHEN leads.status = 'closed' THEN 'new' ELSE leads.status END,
			updated_at = NOW()
		RETURNING id, (xmax = 0)
	`, req.PropertyID, ownerID, buyerID, req.Name, req.Phone, req.Message, req.SourceOrDefault()).Scan(&id, &isNew)
	if err != nil {
		return nil, false, err
	}
	lead, err = r.GetByID(ctx, id)
	return lead, isNew, err
}

func (r *LeadRepository) GetByID(ctx context.Context, id string) (*models.Lead, error) {
	l, err := scanLead(r.db.QueryRow(ctx, leadSelect+` WHERE l.id = $1`, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return l, err
}

// ListByOwner returns the owner's leads (newest first), optionally by status,
// one page at a time (limit<=0 -> 20, max 100).
func (r *LeadRepository) ListByOwner(ctx context.Context, ownerID, status string, page, limit int) ([]models.Lead, int, error) {
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	if page < 1 {
		page = 1
	}

	var total int
	if err := r.db.QueryRow(ctx,
		`SELECT COUNT(*) FROM leads WHERE owner_id = $1 AND ($2::text = '' OR status = $2::text)`,
		ownerID, status).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.db.Query(ctx,
		leadSelect+` WHERE l.owner_id = $1 AND ($2::text = '' OR l.status = $2::text)
		ORDER BY l.updated_at DESC, l.id LIMIT $3 OFFSET $4`,
		ownerID, status, limit, (page-1)*limit)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	leads := []models.Lead{}
	for rows.Next() {
		l, err := scanLead(rows)
		if err != nil {
			return nil, 0, err
		}
		leads = append(leads, *l)
	}
	return leads, total, rows.Err()
}

// ListByBuyer returns the enquiries a buyer has sent.
func (r *LeadRepository) ListByBuyer(ctx context.Context, buyerID string) ([]models.Lead, error) {
	rows, err := r.db.Query(ctx, leadSelect+` WHERE l.buyer_id = $1 ORDER BY l.updated_at DESC LIMIT 200`, buyerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	leads := []models.Lead{}
	for rows.Next() {
		l, err := scanLead(rows)
		if err != nil {
			return nil, err
		}
		leads = append(leads, *l)
	}
	return leads, rows.Err()
}

// UpdateStatus changes a lead's status; only the owning user can (nil if not theirs).
func (r *LeadRepository) UpdateStatus(ctx context.Context, id, ownerID, status string) (*models.Lead, error) {
	tag, err := r.db.Exec(ctx,
		`UPDATE leads SET status = $1, updated_at = NOW() WHERE id = $2 AND owner_id = $3`,
		status, id, ownerID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, nil
	}
	return r.GetByID(ctx, id)
}

func (r *LeadRepository) Counts(ctx context.Context, ownerID string) (*models.LeadCounts, error) {
	var c models.LeadCounts
	err := r.db.QueryRow(ctx, `
		SELECT COUNT(*),
		       COUNT(*) FILTER (WHERE status = 'new'),
		       COUNT(*) FILTER (WHERE status = 'contacted'),
		       COUNT(*) FILTER (WHERE status = 'visited'),
		       COUNT(*) FILTER (WHERE status = 'closed')
		FROM leads WHERE owner_id = $1`, ownerID).Scan(&c.All, &c.New, &c.Contacted, &c.Visited, &c.Closed)
	if err != nil {
		return nil, err
	}
	return &c, nil
}
