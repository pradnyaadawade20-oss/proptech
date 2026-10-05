package repository

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
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

var (
	ErrAgreementLocked   = errors.New("agreement cannot be edited now (already signed, or closed)")
	ErrAgreementBadState = errors.New("this action is not allowed in the agreement's current status")
	ErrOTPNotVerified    = errors.New("verify the OTP before signing")
	ErrOTPInvalid        = errors.New("invalid or expired OTP")
	ErrAlreadySigned     = errors.New("you have already signed this agreement")
)

func hashOTP(agreementID, role, code string) string {
	h := sha256.Sum256([]byte(agreementID + ":" + role + ":" + code))
	return hex.EncodeToString(h[:])
}

// UpdateDraft fills in the terms and moves status -> draft_ready.
// Locked once anyone has signed or the agreement is closed.
func (r *AgreementRepository) UpdateDraft(ctx context.Context, id string, req models.UpdateDraftRequest) (*models.Agreement, error) {
	tag, err := r.db.Exec(ctx, `
		UPDATE agreements
		SET monthly_rent = $1, security_deposit = $2, start_date = $3,
		    duration_months = $4, terms = $5, status = 'draft_ready', updated_at = now(),
		    owner_otp_verified = FALSE, tenant_otp_verified = FALSE,
		    owner_otp_code = NULL, tenant_otp_code = NULL
		WHERE id = $6
		  AND status IN ('requested', 'draft_ready', 'awaiting_signatures')
		  AND owner_signed_at IS NULL AND tenant_signed_at IS NULL
	`, req.MonthlyRent, req.SecurityDeposit, req.StartDate, req.DurationMonths, req.Terms, id)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrAgreementLocked
	}
	return r.GetByID(ctx, id)
}

// PartyEmail returns the email of the owner or tenant on the agreement.
func (r *AgreementRepository) PartyEmail(ctx context.Context, id, role string) (string, error) {
	col := "a.tenant_id"
	if role == "owner" {
		col = "a.owner_id"
	}
	var email string
	err := r.db.QueryRow(ctx, `SELECT COALESCE(u.email,'') FROM agreements a JOIN users u ON u.id = `+col+` WHERE a.id = $1`, id).Scan(&email)
	return email, err
}

// SetOTP stores a hashed 6-digit code (10 min validity) for the party.
func (r *AgreementRepository) SetOTP(ctx context.Context, id, role, code string) error {
	q := `UPDATE agreements SET tenant_otp_code=$1, tenant_otp_expires_at=now()+interval '10 minutes', tenant_otp_verified=FALSE, updated_at=now() WHERE id=$2`
	if role == "owner" {
		q = `UPDATE agreements SET owner_otp_code=$1, owner_otp_expires_at=now()+interval '10 minutes', owner_otp_verified=FALSE, updated_at=now() WHERE id=$2`
	}
	_, err := r.db.Exec(ctx, q, hashOTP(id, role, code), id)
	return err
}

// VerifyOTP marks the party's OTP verified if the code matches and is unexpired.
func (r *AgreementRepository) VerifyOTP(ctx context.Context, id, role, code string) error {
	q := `UPDATE agreements SET tenant_otp_verified=TRUE, tenant_otp_code=NULL
	      WHERE id=$1 AND tenant_otp_code=$2 AND tenant_otp_expires_at > now()`
	if role == "owner" {
		q = `UPDATE agreements SET owner_otp_verified=TRUE, owner_otp_code=NULL
		     WHERE id=$1 AND owner_otp_code=$2 AND owner_otp_expires_at > now()`
	}
	tag, err := r.db.Exec(ctx, q, id, hashOTP(id, role, code))
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrOTPInvalid
	}
	return nil
}

// Sign records a signature for owner or tenant. Requires: draft is final
// (not "requested"), the party's OTP is verified, party hasn't signed yet.
// Status is computed in the same atomic UPDATE. Both signed -> completed.
func (r *AgreementRepository) Sign(ctx context.Context, id string, req models.SignAgreementRequest) (*models.Agreement, error) {
	current, err := r.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	switch current.Status {
	case "draft_ready", "awaiting_signatures", "signed_by_owner", "signed_by_tenant":
	default:
		return nil, ErrAgreementBadState
	}

	var verified bool
	col := "tenant"
	if req.SignerRole == "owner" {
		col = "owner"
		if current.OwnerSignedAt != nil {
			return nil, ErrAlreadySigned
		}
	} else if current.TenantSignedAt != nil {
		return nil, ErrAlreadySigned
	}
	if err := r.db.QueryRow(ctx, `SELECT `+col+`_otp_verified FROM agreements WHERE id=$1`, id).Scan(&verified); err != nil {
		return nil, err
	}
	if !verified {
		return nil, ErrOTPNotVerified
	}

	otherSigned := current.TenantSignedAt != nil
	newStatus := "signed_by_owner"
	if req.SignerRole == "tenant" {
		otherSigned = current.OwnerSignedAt != nil
		newStatus = "signed_by_tenant"
	}
	if otherSigned {
		newStatus = "completed"
	}

	_, err = r.db.Exec(ctx, `
		UPDATE agreements
		SET `+col+`_signature_type = $1, `+col+`_signature_data = $2, `+col+`_signed_at = now(),
		    `+col+`_otp_verified = FALSE, status = $3, updated_at = now()
		WHERE id = $4
	`, req.SignatureType, req.SignatureData, newStatus, id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

// UpdateStatus validates the transition against models.AgreementTransitions.
func (r *AgreementRepository) UpdateStatus(ctx context.Context, id string, status string) (*models.Agreement, error) {
	current, err := r.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if !models.AgreementCanMove(current.Status, status) {
		return nil, ErrAgreementBadState
	}
	_, err = r.db.Exec(ctx, `UPDATE agreements SET status = $1, updated_at = now() WHERE id = $2 AND status = $3`, status, id, current.Status)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}