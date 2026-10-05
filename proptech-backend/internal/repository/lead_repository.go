package repository

import (
	"context"
	"errors"
	"fmt"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrLeadOwnProperty = errors.New("you can't enquire on your own property")
	ErrLeadNoOwner     = errors.New("this property has no owner to contact")
)

type LeadRepository struct {
	db *pgxpool.Pool
}

func NewLeadRepository(db *pgxpool.Pool) *LeadRepository {
	return &LeadRepository{db: db}
}

const leadSelectQuery = `
	SELECT l.id, l.property_id, p.title, COALESCE(p.image_url, ''), l.owner_id, l.buyer_id,
	       l.name, l.phone, COALESCE(bu.email, ''), l.message, l.source, l.status, l.created_at, l.updated_at
	FROM leads l
	JOIN properties p ON p.id = l.property_id
	LEFT JOIN users bu ON bu.id = l.buyer_id
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

func (r *LeadRepository) GetByID(ctx context.Context, id string) (*models.Lead, error) {
	return scanLead(r.db.QueryRow(ctx, leadSelectQuery+` WHERE l.id = $1`, id))
}

// Upsert creates the lead (name/phone copied from the buyer's profile) or, if
// the buyer already enquired on this property, just refreshes message/updated_at.
// Status is never reset. created=true only when a new row was inserted.
func (r *LeadRepository) Upsert(ctx context.Context, propertyID, buyerID, name, phone, source, message string) (lead *models.Lead, created bool, err error) {
	var ownerID *string
	if err = r.db.QueryRow(ctx, `SELECT owner_id FROM properties WHERE id = $1`, propertyID).Scan(&ownerID); err != nil {
		return nil, false, err
	}
	if ownerID == nil {
		return nil, false, ErrLeadNoOwner
	}
	if *ownerID == buyerID {
		return nil, false, ErrLeadOwnProperty
	}
	if source == "" {
		source = "contact"
	}

	var id string
	err = r.db.QueryRow(ctx, `
		INSERT INTO leads (property_id, owner_id, buyer_id, name, phone, message, source)
		SELECT $1::uuid, $2::uuid, u.id, COALESCE(NULLIF($4::text, ''), u.name, ''), COALESCE(NULLIF($5::text, ''), u.phone, ''), $6::text, $7::text
		FROM users u WHERE u.id = $3
		ON CONFLICT (property_id, buyer_id) DO UPDATE
		SET message = CASE WHEN EXCLUDED.message <> '' THEN EXCLUDED.message ELSE leads.message END,
		    name    = CASE WHEN $4::text <> '' THEN EXCLUDED.name  ELSE leads.name  END,
		    phone   = CASE WHEN $5::text <> '' THEN EXCLUDED.phone ELSE leads.phone END,
		    updated_at = now()
		RETURNING id, (xmax = 0)
	`, propertyID, *ownerID, buyerID, name, phone, source, message).Scan(&id, &created)
	if err != nil {
		return nil, false, err
	}
	lead, err = r.GetByID(ctx, id)
	return lead, created, err
}

// ListByOwner: leads on my properties, optional status filter, paginated.
// Returns the page plus the total number of matching rows.
func (r *LeadRepository) ListByOwner(ctx context.Context, ownerID, status string, limit, offset int) ([]models.Lead, int, error) {
	where := ` WHERE l.owner_id = $1`
	args := []any{ownerID}
	if status != "" {
		where += ` AND l.status = $2`
		args = append(args, status)
	}
	var total int
	if err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM leads l`+where, args...).Scan(&total); err != nil {
		return nil, 0, err
	}
	n := len(args)
	leads, err := r.list(ctx, leadSelectQuery+where+
		fmt.Sprintf(` ORDER BY l.updated_at DESC LIMIT $%d OFFSET $%d`, n+1, n+2),
		append(args, limit, offset)...)
	return leads, total, err
}

// CountsByOwner: per-status totals for the tab badges (ignores the status filter).
func (r *LeadRepository) CountsByOwner(ctx context.Context, ownerID string) (models.LeadCounts, error) {
	var c models.LeadCounts
	rows, err := r.db.Query(ctx, `SELECT status, COUNT(*) FROM leads WHERE owner_id = $1 GROUP BY status`, ownerID)
	if err != nil {
		return c, err
	}
	defer rows.Close()
	for rows.Next() {
		var st string
		var n int
		if err := rows.Scan(&st, &n); err != nil {
			return c, err
		}
		switch st {
		case "new":
			c.New = n
		case "contacted":
			c.Contacted = n
		case "visited":
			c.Visited = n
		case "closed":
			c.Closed = n
		}
		c.All += n
	}
	return c, rows.Err()
}

// OwnerContact: the owner's name + phone, shown to the buyer after an enquiry.
func (r *LeadRepository) OwnerContact(ctx context.Context, ownerID string) (name, phone string, err error) {
	err = r.db.QueryRow(ctx, `SELECT COALESCE(name, ''), COALESCE(phone, '') FROM users WHERE id = $1`, ownerID).Scan(&name, &phone)
	return
}

// ListByBuyer: enquiries I made.
func (r *LeadRepository) ListByBuyer(ctx context.Context, buyerID string) ([]models.Lead, error) {
	return r.list(ctx, leadSelectQuery+` WHERE l.buyer_id = $1 ORDER BY l.updated_at DESC`, buyerID)
}

func (r *LeadRepository) list(ctx context.Context, q string, args ...any) ([]models.Lead, error) {
	rows, err := r.db.Query(ctx, q, args...)
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

// SetStatus: owner sets the status manually (any direction).
func (r *LeadRepository) SetStatus(ctx context.Context, id, status string) (*models.Lead, error) {
	if _, err := r.db.Exec(ctx, `UPDATE leads SET status = $1, updated_at = now() WHERE id = $2`, status, id); err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

// Advance is the AUTO status mover: only moves forward, never backward,
// silently does nothing if there's no lead. Used by chat / visit / agreement hooks.
func (r *LeadRepository) Advance(ctx context.Context, propertyID, buyerID, to string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE leads SET status = $3::text, updated_at = now()
		WHERE property_id = $1 AND buyer_id = $2
		  AND (`+leadRankSQL("status")+`) < (`+leadRankSQL("$3::text")+`)
	`, propertyID, buyerID, to)
	return err
}

func leadRankSQL(col string) string {
	return `CASE ` + col + ` WHEN 'new' THEN 0 WHEN 'contacted' THEN 1 WHEN 'visited' THEN 2 ELSE 3 END`
}

// TouchChat is called after every chat message that carries a property_id:
//   - buyer -> owner : lead is created (source "chat") if missing
//   - owner -> buyer : lead moves new -> contacted
func (r *LeadRepository) TouchChat(ctx context.Context, propertyID, senderID, receiverID, text string) error {
	var ownerID *string
	if err := r.db.QueryRow(ctx, `SELECT owner_id FROM properties WHERE id = $1`, propertyID).Scan(&ownerID); err != nil || ownerID == nil {
		return err
	}
	switch {
	case *ownerID == senderID:
		return r.Advance(ctx, propertyID, receiverID, "contacted")
	case *ownerID == receiverID:
		_, _, err := r.Upsert(ctx, propertyID, senderID, "", "", "chat", text)
		return err
	}
	return nil
}
