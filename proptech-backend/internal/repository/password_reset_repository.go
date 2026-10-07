package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PasswordReset struct {
	Email      string
	OTPHash    string
	Attempts   int
	ExpiresAt  time.Time
	LastSentAt time.Time
}

type PasswordResetRepository struct {
	db *pgxpool.Pool
}

func NewPasswordResetRepository(db *pgxpool.Pool) *PasswordResetRepository {
	return &PasswordResetRepository{db: db}
}

// Get returns (nil, nil) when there is no pending reset for this email.
func (r *PasswordResetRepository) Get(ctx context.Context, email string) (*PasswordReset, error) {
	var p PasswordReset
	err := r.db.QueryRow(ctx, `
		SELECT email, otp_hash, attempts, expires_at, last_sent_at
		FROM password_resets WHERE email = $1
	`, strings.ToLower(email)).Scan(&p.Email, &p.OTPHash, &p.Attempts, &p.ExpiresAt, &p.LastSentAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &p, nil
}

// Upsert replaces any previous code for this email and resets attempts.
func (r *PasswordResetRepository) Upsert(ctx context.Context, email, otpHash string, expiresAt time.Time) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO password_resets (email, otp_hash, attempts, expires_at, last_sent_at)
		VALUES ($1, $2, 0, $3, NOW())
		ON CONFLICT (email) DO UPDATE
		SET otp_hash = EXCLUDED.otp_hash,
		    attempts = 0,
		    expires_at = EXCLUDED.expires_at,
		    last_sent_at = NOW()
	`, strings.ToLower(email), otpHash, expiresAt)
	return err
}

// IncrementAttempts bumps and returns the counter. Call it BEFORE comparing
// the code so parallel guesses can't dodge the limit.
func (r *PasswordResetRepository) IncrementAttempts(ctx context.Context, email string) (int, error) {
	var n int
	err := r.db.QueryRow(ctx, `
		UPDATE password_resets SET attempts = attempts + 1 WHERE email = $1 RETURNING attempts
	`, strings.ToLower(email)).Scan(&n)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, nil
		}
		return 0, err
	}
	return n, nil
}

func (r *PasswordResetRepository) Delete(ctx context.Context, email string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM password_resets WHERE email = $1`, strings.ToLower(email))
	return err
}