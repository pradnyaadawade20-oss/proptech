package repository

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type EmailOTP struct {
	Email        string
	OTPHash      string
	Name         string
	PasswordHash string
	Attempts     int
	ExpiresAt    time.Time
	LastSentAt   time.Time
}

type EmailOTPRepository struct {
	db *pgxpool.Pool
}

func NewEmailOTPRepository(db *pgxpool.Pool) *EmailOTPRepository {
	return &EmailOTPRepository{db: db}
}

func (r *EmailOTPRepository) Get(ctx context.Context, email string) (*EmailOTP, error) {
	var o EmailOTP
	err := r.db.QueryRow(ctx, `
		SELECT email, otp_hash, name, password_hash, attempts, expires_at, last_sent_at
		FROM email_otps WHERE email = $1
	`, strings.ToLower(email)).Scan(&o.Email, &o.OTPHash, &o.Name, &o.PasswordHash, &o.Attempts, &o.ExpiresAt, &o.LastSentAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &o, nil
}

// Upsert replaces any previous OTP for this email and resets attempts.
func (r *EmailOTPRepository) Upsert(ctx context.Context, email, otpHash, name, passwordHash string, expiresAt time.Time) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO email_otps (email, otp_hash, name, password_hash, attempts, expires_at, last_sent_at)
		VALUES ($1, $2, $3, $4, 0, $5, NOW())
		ON CONFLICT (email) DO UPDATE
		SET otp_hash = EXCLUDED.otp_hash,
		    name = EXCLUDED.name,
		    password_hash = EXCLUDED.password_hash,
		    attempts = 0,
		    expires_at = EXCLUDED.expires_at,
		    last_sent_at = NOW()
	`, strings.ToLower(email), otpHash, name, passwordHash, expiresAt)
	return err
}

// IncrementAttempts atomically bumps and returns the attempt counter. Called
// BEFORE comparing the code so parallel guesses can't dodge the limit.
func (r *EmailOTPRepository) IncrementAttempts(ctx context.Context, email string) (int, error) {
	var n int
	err := r.db.QueryRow(ctx, `
		UPDATE email_otps SET attempts = attempts + 1 WHERE email = $1 RETURNING attempts
	`, strings.ToLower(email)).Scan(&n)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return 0, nil
		}
		return 0, err
	}
	return n, nil
}

func (r *EmailOTPRepository) Delete(ctx context.Context, email string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM email_otps WHERE email = $1`, strings.ToLower(email))
	return err
}
