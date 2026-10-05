package repository

import (
	"context"
	"errors"
	"fmt"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrKYCAlreadyVerified = errors.New("KYC is already verified")
	ErrKYCCooldown        = errors.New("please wait a little before requesting another OTP")
	ErrKYCNoActiveOTP     = errors.New("OTP expired or not requested, send a new OTP")
	ErrKYCAadhaarInUse    = errors.New("this Aadhaar is already linked to another account")
)

const (
	KYCResendCooldownSeconds = 30
	KYCOTPValidityMinutes    = 10
	KYCMaxAttempts           = 5
)

type KYCRepository struct {
	db *pgxpool.Pool
}

func NewKYCRepository(db *pgxpool.Pool) *KYCRepository {
	return &KYCRepository{db: db}
}

// Get returns the user's KYC row, or (nil, nil) if they never started.
func (r *KYCRepository) Get(ctx context.Context, userID string) (*models.KYC, error) {
	var k models.KYC
	var last4 string
	err := r.db.QueryRow(ctx, `
		SELECT status, aadhaar_last4, verified_at, otp_sent_at
		FROM user_kyc WHERE user_id = $1
	`, userID).Scan(&k.Status, &last4, &k.VerifiedAt, &k.OTPSentAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	if k.Status == models.KYCVerified || k.Status == models.KYCPending {
		k.MaskedAadhaar = fmt.Sprintf("XXXX XXXX %s", last4)
	}
	return &k, nil
}

// IsVerified is the check other flows (agreement signing, later sale/offers) call.
func (r *KYCRepository) IsVerified(ctx context.Context, userID string) (bool, error) {
	var ok bool
	err := r.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM user_kyc WHERE user_id = $1 AND status = 'verified')`, userID).Scan(&ok)
	return ok, err
}

// StartOTP records a freshly sent OTP (status -> pending, attempts reset).
// Refuses if already verified or if the previous OTP was sent < cooldown ago.
func (r *KYCRepository) StartOTP(ctx context.Context, userID, aadhaarHash, last4, provider, providerRef string) error {
	tag, err := r.db.Exec(ctx, `
		INSERT INTO user_kyc (user_id, status, aadhaar_hash, aadhaar_last4, provider, provider_ref, attempts, otp_sent_at)
		VALUES ($1, 'pending', $2, $3, $4, $5, 0, now())
		ON CONFLICT (user_id) DO UPDATE
		SET status = 'pending', aadhaar_hash = EXCLUDED.aadhaar_hash, aadhaar_last4 = EXCLUDED.aadhaar_last4,
		    provider = EXCLUDED.provider, provider_ref = EXCLUDED.provider_ref,
		    attempts = 0, otp_sent_at = now(), rejected_reason = NULL, updated_at = now()
		WHERE user_kyc.status <> 'verified'
		  AND (user_kyc.otp_sent_at IS NULL OR user_kyc.otp_sent_at < now() - ($6::int * interval '1 second'))
	`, userID, aadhaarHash, last4, provider, providerRef, KYCResendCooldownSeconds)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		if ok, _ := r.IsVerified(ctx, userID); ok {
			return ErrKYCAlreadyVerified
		}
		return ErrKYCCooldown
	}
	return nil
}

// RegisterAttempt atomically bumps the wrong-guess counter BEFORE the code is
// checked (so parallel guesses can't dodge the limit) and returns the provider
// reference to verify against. Fails if there's no live (unexpired) OTP.
func (r *KYCRepository) RegisterAttempt(ctx context.Context, userID string) (providerRef string, attempts int, err error) {
	err = r.db.QueryRow(ctx, `
		UPDATE user_kyc
		SET attempts = attempts + 1, updated_at = now()
		WHERE user_id = $1 AND status = 'pending'
		  AND otp_sent_at > now() - ($2::int * interval '1 minute')
		RETURNING COALESCE(provider_ref, ''), attempts
	`, userID, KYCOTPValidityMinutes).Scan(&providerRef, &attempts)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", 0, ErrKYCNoActiveOTP
	}
	return providerRef, attempts, err
}

// MarkVerified flips pending -> verified. A unique index guarantees one
// verified Aadhaar per account; a clash comes back as ErrKYCAadhaarInUse.
func (r *KYCRepository) MarkVerified(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE user_kyc
		SET status = 'verified', verified_at = now(), provider_ref = NULL, attempts = 0, updated_at = now()
		WHERE user_id = $1 AND status = 'pending'
	`, userID)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return ErrKYCAadhaarInUse
	}
	return err
}

// MarkRejected closes a pending attempt (e.g. too many wrong OTPs). The user
// can start over with a new send-otp.
func (r *KYCRepository) MarkRejected(ctx context.Context, userID, reason string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE user_kyc
		SET status = 'rejected', rejected_reason = $2, provider_ref = NULL, updated_at = now()
		WHERE user_id = $1 AND status = 'pending'
	`, userID, reason)
	return err
}
