package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"proptech-backend/internal/models"
)

type AgreementRepository struct {
	db *pgxpool.Pool
}

func NewAgreementRepository(db *pgxpool.Pool) *AgreementRepository {
	return &AgreementRepository{db: db}
}

const agreementSelectQuery = `
	SELECT a.id, a.property_id, p.title, p.image_url,
	       a.owner_id, ou.name, a.tenant_id, tu.name,
	       a.status, a.monthly_rent, a.security_deposit, a.start_date, a.duration_months, a.terms,
	       COALESCE(a.owner_signature_type, ''), COALESCE(a.owner_signature_data, ''), a.owner_signed_at,
	       COALESCE(a.tenant_signature_type, ''), COALESCE(a.tenant_signature_data, ''), a.tenant_signed_at,
	       COALESCE(a.final_pdf_url, ''), a.created_at, a.updated_at
	FROM agreements a
	JOIN properties p ON p.id = a.property_id
	JOIN users ou ON ou.id = a.owner_id
	JOIN users tu ON tu.id = a.tenant_id
`

func scanAgreement(row interface{ Scan(dest ...any) error }) (*models.Agreement, error) {
	var a models.Agreement
	var startDate *time.Time
	err := row.Scan(
		&a.ID, &a.PropertyID, &a.PropertyTitle, &a.PropertyImageURL,
		&a.OwnerID, &a.OwnerName, &a.TenantID, &a.TenantName,
		&a.Status, &a.MonthlyRent, &a.SecurityDeposit, &startDate, &a.DurationMonths, &a.Terms,
		&a.OwnerSignatureType, &a.OwnerSignatureData, &a.OwnerSignedAt,
		&a.TenantSignatureType, &a.TenantSignatureData, &a.TenantSignedAt,
		&a.FinalPDFURL, &a.CreatedAt, &a.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	if startDate != nil {
		s := startDate.Format("2006-01-02")
		a.StartDate = &s
	}
	return &a, nil
}

func (r *AgreementRepository) Create(ctx context.Context, req models.CreateAgreementRequest) (*models.Agreement, error) {
	var id string
	err := r.db.QueryRow(ctx, `
		INSERT INTO agreements (property_id, owner_id, tenant_id, status)
		VALUES ($1, $2, $3, 'requested')
		RETURNING id
	`, req.PropertyID, req.OwnerID, req.TenantID).Scan(&id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

func (r *AgreementRepository) GetByID(ctx context.Context, id string) (*models.Agreement, error) {
	row := r.db.QueryRow(ctx, agreementSelectQuery+` WHERE a.id = $1`, id)
	return scanAgreement(row)
}

// GetByUserID returns agreements where the user is either the owner or the tenant.
func (r *AgreementRepository) GetByUserID(ctx context.Context, userID string) ([]models.Agreement, error) {
	rows, err := r.db.Query(ctx, agreementSelectQuery+`
		WHERE a.owner_id = $1 OR a.tenant_id = $1
		ORDER BY a.updated_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var agreements []models.Agreement
	for rows.Next() {
		a, err := scanAgreement(rows)
		if err != nil {
			return nil, err
		}
		agreements = append(agreements, *a)
	}
	return agreements, nil
}

// UpdateDraft fills in the terms and moves status -> draft_ready.
func (r *AgreementRepository) UpdateDraft(ctx context.Context, id string, req models.UpdateDraftRequest) (*models.Agreement, error) {
	_, err := r.db.Exec(ctx, `
		UPDATE agreements
		SET monthly_rent = $1, security_deposit = $2, start_date = $3,
		    duration_months = $4, terms = $5, status = 'draft_ready', updated_at = now()
		WHERE id = $6
	`, req.MonthlyRent, req.SecurityDeposit, req.StartDate, req.DurationMonths, req.Terms, id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

// Sign records a signature (drawn PNG or typed name) for owner or tenant,
// and advances the status accordingly. Once both have signed -> completed.
func (r *AgreementRepository) Sign(ctx context.Context, id string, req models.SignAgreementRequest) (*models.Agreement, error) {
	current, err := r.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}

	var newStatus string
	if req.SignerRole == "owner" {
		_, err = r.db.Exec(ctx, `
			UPDATE agreements
			SET owner_signature_type = $1, owner_signature_data = $2, owner_signed_at = now(), updated_at = now()
			WHERE id = $3
		`, req.SignatureType, req.SignatureData, id)
		if current.TenantSignedAt != nil {
			newStatus = "completed"
		} else {
			newStatus = "signed_by_owner"
		}
	} else {
		_, err = r.db.Exec(ctx, `
			UPDATE agreements
			SET tenant_signature_type = $1, tenant_signature_data = $2, tenant_signed_at = now(), updated_at = now()
			WHERE id = $3
		`, req.SignatureType, req.SignatureData, id)
		if current.OwnerSignedAt != nil {
			newStatus = "completed"
		} else {
			newStatus = "signed_by_tenant"
		}
	}
	if err != nil {
		return nil, err
	}

	_, err = r.db.Exec(ctx, `UPDATE agreements SET status = $1, updated_at = now() WHERE id = $2`, newStatus, id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

func (r *AgreementRepository) UpdateStatus(ctx context.Context, id string, status string) (*models.Agreement, error) {
	_, err := r.db.Exec(ctx, `UPDATE agreements SET status = $1, updated_at = now() WHERE id = $2`, status, id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}