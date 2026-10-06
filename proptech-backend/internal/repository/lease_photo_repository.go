package repository

import (
	"context"
	"errors"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
)

// ---------------------------------------------------------------------------
// Photos (move-in, move-out, damage proof, maintenance)
// ---------------------------------------------------------------------------

const photoSelect = `
	SELECT ph.id, ph.lease_id, ph.uploader_id, COALESCE(u.name, ''), ph.kind, ph.room, ph.caption,
	       ph.deduction_id, ph.ticket_id, ph.created_at
	FROM lease_photos ph
	LEFT JOIN users u ON u.id = ph.uploader_id
`

func scanPhoto(row interface{ Scan(dest ...any) error }) (*models.LeasePhoto, error) {
	var p models.LeasePhoto
	err := row.Scan(&p.ID, &p.LeaseID, &p.UploaderID, &p.UploaderName, &p.Kind, &p.Room, &p.Caption,
		&p.DeductionID, &p.TicketID, &p.CreatedAt)
	if err != nil {
		return nil, err
	}
	p.URL = "/api/leases/" + p.LeaseID + "/photos/" + p.ID
	return &p, nil
}

func collectPhotos(rows pgx.Rows) ([]models.LeasePhoto, error) {
	defer rows.Close()
	out := []models.LeasePhoto{}
	for rows.Next() {
		p, err := scanPhoto(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *p)
	}
	return out, rows.Err()
}

// ListPhotos returns photo metadata (never the bytes). kind "" = all kinds.
func (r *LeaseRepository) ListPhotos(ctx context.Context, leaseID, kind string) ([]models.LeasePhoto, error) {
	rows, err := r.db.Query(ctx, photoSelect+`
		WHERE ph.lease_id = $1 AND ($2::text = '' OR ph.kind = $2::text)
		ORDER BY ph.created_at`, leaseID, kind)
	if err != nil {
		return nil, err
	}
	return collectPhotos(rows)
}

func (r *LeaseRepository) ListTicketPhotos(ctx context.Context, ticketID string) ([]models.LeasePhoto, error) {
	rows, err := r.db.Query(ctx, photoSelect+` WHERE ph.ticket_id = $1 ORDER BY ph.created_at`, ticketID)
	if err != nil {
		return nil, err
	}
	return collectPhotos(rows)
}

func (r *LeaseRepository) CountPhotos(ctx context.Context, leaseID, kind string, deductionID, ticketID *string) (int, error) {
	var n int
	err := r.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM lease_photos
		WHERE lease_id = $1 AND kind = $2
		  AND ($3::uuid IS NULL OR deduction_id = $3::uuid)
		  AND ($4::uuid IS NULL OR ticket_id = $4::uuid)`,
		leaseID, kind, deductionID, ticketID).Scan(&n)
	return n, err
}

func (r *LeaseRepository) AddPhoto(ctx context.Context, leaseID, uploaderID, kind, room, caption string,
	deductionID, ticketID *string, contentType string, data []byte) (string, error) {
	var id string
	err := r.db.QueryRow(ctx, `
		INSERT INTO lease_photos (lease_id, uploader_id, kind, room, caption, deduction_id, ticket_id, content_type, data)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id`,
		leaseID, uploaderID, kind, room, caption, deductionID, ticketID, contentType, data).Scan(&id)
	return id, err
}

// GetPhotoMeta returns the photo's metadata only (for permission checks).
func (r *LeaseRepository) GetPhotoMeta(ctx context.Context, leaseID, photoID string) (*models.LeasePhoto, error) {
	p, err := scanPhoto(r.db.QueryRow(ctx, photoSelect+` WHERE ph.id = $1 AND ph.lease_id = $2`, photoID, leaseID))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrLeaseNotFound
		}
		return nil, err
	}
	return p, nil
}

func (r *LeaseRepository) GetPhotoData(ctx context.Context, leaseID, photoID string) ([]byte, string, error) {
	var data []byte
	var ct string
	err := r.db.QueryRow(ctx,
		`SELECT data, content_type FROM lease_photos WHERE id = $1 AND lease_id = $2`, photoID, leaseID).Scan(&data, &ct)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, "", ErrLeaseNotFound
		}
		return nil, "", err
	}
	return data, ct, nil
}

func (r *LeaseRepository) DeletePhoto(ctx context.Context, leaseID, photoID string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM lease_photos WHERE id = $1 AND lease_id = $2`, photoID, leaseID)
	return err
}

// ---------------------------------------------------------------------------
// Maintenance tickets
// ---------------------------------------------------------------------------

const ticketSelect = `
	SELECT t.id, t.lease_id, t.property_id, p.title, t.tenant_id, tu.name, t.owner_id,
	       t.title, t.description, t.category, t.priority, t.status, t.resolved_at, t.created_at, t.updated_at,
	       (SELECT COUNT(*) FROM lease_photos ph WHERE ph.ticket_id = t.id)
	FROM maintenance_tickets t
	JOIN properties p ON p.id = t.property_id
	JOIN users tu ON tu.id = t.tenant_id
`

func scanTicket(row interface{ Scan(dest ...any) error }) (*models.Ticket, error) {
	var t models.Ticket
	err := row.Scan(&t.ID, &t.LeaseID, &t.PropertyID, &t.PropertyTitle, &t.TenantID, &t.TenantName, &t.OwnerID,
		&t.Title, &t.Description, &t.Category, &t.Priority, &t.Status, &t.ResolvedAt, &t.CreatedAt, &t.UpdatedAt,
		&t.PhotoCount)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

func (r *LeaseRepository) CreateTicket(ctx context.Context, l *models.Lease, title, description, category, priority string) (string, error) {
	if l.Status != "active" && l.Status != "notice_given" {
		return "", badState("issues can only be reported during an active tenancy")
	}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return "", err
	}
	defer tx.Rollback(ctx)
	var id string
	err = tx.QueryRow(ctx, `
		INSERT INTO maintenance_tickets (lease_id, property_id, tenant_id, owner_id, title, description, category, priority)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id`, l.ID, l.PropertyID, l.TenantID, l.OwnerID, title, description, category, priority).Scan(&id)
	if err != nil {
		return "", err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO maintenance_updates (ticket_id, actor_id, status, note) VALUES ($1, $2, 'reported', $3)`,
		id, l.TenantID, description); err != nil {
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return id, nil
}

func (r *LeaseRepository) ListTickets(ctx context.Context, leaseID string) ([]models.Ticket, error) {
	rows, err := r.db.Query(ctx, ticketSelect+` WHERE t.lease_id = $1 ORDER BY t.created_at DESC`, leaseID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []models.Ticket{}
	for rows.Next() {
		t, err := scanTicket(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *t)
	}
	return out, rows.Err()
}

// GetTicket returns the ticket with its timeline and photos.
func (r *LeaseRepository) GetTicket(ctx context.Context, id string) (*models.Ticket, error) {
	t, err := scanTicket(r.db.QueryRow(ctx, ticketSelect+` WHERE t.id = $1`, id))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrLeaseNotFound
		}
		return nil, err
	}
	rows, err := r.db.Query(ctx, `
		SELECT mu.id, mu.actor_id, COALESCE(u.name, ''), mu.status, mu.note, mu.created_at
		FROM maintenance_updates mu LEFT JOIN users u ON u.id = mu.actor_id
		WHERE mu.ticket_id = $1 ORDER BY mu.created_at`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	t.Updates = []models.TicketUpdate{}
	for rows.Next() {
		var u models.TicketUpdate
		if err := rows.Scan(&u.ID, &u.ActorID, &u.ActorName, &u.Status, &u.Note, &u.CreatedAt); err != nil {
			return nil, err
		}
		t.Updates = append(t.Updates, u)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rows.Close()
	t.Photos, err = r.ListTicketPhotos(ctx, id)
	if err != nil {
		return nil, err
	}
	return t, nil
}

// UpdateTicketStatus: owner -> in_progress / resolved. Tenant -> reopen (only after resolved).
func (r *LeaseRepository) UpdateTicketStatus(ctx context.Context, t *models.Ticket, actorID, role, action, note string) error {
	newStatus := ""
	switch {
	case role == "owner" && action == "in_progress" && (t.Status == "reported" || t.Status == "resolved"):
		newStatus = "in_progress"
	case role == "owner" && action == "resolved" && t.Status != "resolved":
		newStatus = "resolved"
	case role == "tenant" && action == "reopen" && t.Status == "resolved":
		newStatus = "reported"
	default:
		return badState("this status change is not allowed")
	}
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `
		UPDATE maintenance_tickets
		SET status = $2, updated_at = now(),
		    resolved_at = CASE WHEN $2::text = 'resolved' THEN now() ELSE NULL END
		WHERE id = $1 AND status = $3`, t.ID, newStatus, t.Status)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return badState("the issue was just updated, please refresh")
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO maintenance_updates (ticket_id, actor_id, status, note) VALUES ($1, $2, $3, $4)`,
		t.ID, actorID, newStatus, note); err != nil {
		return err
	}
	return tx.Commit(ctx)
}