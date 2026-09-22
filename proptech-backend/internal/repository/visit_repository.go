package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"proptech-backend/internal/models"
)

type VisitRepository struct {
	db *pgxpool.Pool
}

func NewVisitRepository(db *pgxpool.Pool) *VisitRepository {
	return &VisitRepository{db: db}
}

const visitSelectQuery = `
	SELECT v.id, v.property_id, p.title, p.image_url, v.visitor_id, u.name, v.scheduled_at, v.status, v.created_at
	FROM visits v
	JOIN properties p ON p.id = v.property_id
	JOIN users u ON u.id = v.visitor_id
`

func scanVisit(row interface {
	Scan(dest ...any) error
}) (*models.Visit, error) {
	var v models.Visit
	err := row.Scan(&v.ID, &v.PropertyID, &v.PropertyTitle, &v.PropertyImageURL, &v.VisitorID, &v.VisitorName, &v.ScheduledAt, &v.Status, &v.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &v, nil
}

// GetByVisitorID returns all visits scheduled by a given tenant/buyer (visitor).
func (r *VisitRepository) GetByVisitorID(ctx context.Context, visitorID string) ([]models.Visit, error) {
	rows, err := r.db.Query(ctx, visitSelectQuery+` WHERE v.visitor_id = $1 ORDER BY v.scheduled_at DESC`, visitorID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var visits []models.Visit
	for rows.Next() {
		v, err := scanVisit(rows)
		if err != nil {
			return nil, err
		}
		visits = append(visits, *v)
	}
	return visits, nil
}

// GetByOwnerID returns all visits for properties owned by a given owner
// (used by the Owner Dashboard to see who's visiting their listings).
func (r *VisitRepository) GetByOwnerID(ctx context.Context, ownerID string) ([]models.Visit, error) {
	rows, err := r.db.Query(ctx, visitSelectQuery+` WHERE p.owner_id = $1 ORDER BY v.scheduled_at DESC`, ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var visits []models.Visit
	for rows.Next() {
		v, err := scanVisit(rows)
		if err != nil {
			return nil, err
		}
		visits = append(visits, *v)
	}
	return visits, nil
}

func (r *VisitRepository) GetByID(ctx context.Context, id string) (*models.Visit, error) {
	row := r.db.QueryRow(ctx, visitSelectQuery+` WHERE v.id = $1`, id)
	return scanVisit(row)
}

func (r *VisitRepository) Create(ctx context.Context, req models.CreateVisitRequest) (*models.Visit, error) {
	var id string
	err := r.db.QueryRow(ctx, `
		INSERT INTO visits (property_id, visitor_id, scheduled_at, status)
		VALUES ($1, $2, $3, 'pending')
		RETURNING id
	`, req.PropertyID, req.VisitorID, req.ScheduledAt).Scan(&id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

func (r *VisitRepository) UpdateStatus(ctx context.Context, id string, status string) (*models.Visit, error) {
	_, err := r.db.Exec(ctx, `UPDATE visits SET status = $1 WHERE id = $2`, status, id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

func (r *VisitRepository) Delete(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM visits WHERE id = $1`, id)
	return err
}