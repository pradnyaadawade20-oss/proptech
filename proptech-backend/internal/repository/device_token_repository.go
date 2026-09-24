package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"proptech-backend/internal/models"
)

type DeviceTokenRepository struct {
	db *pgxpool.Pool
}

func NewDeviceTokenRepository(db *pgxpool.Pool) *DeviceTokenRepository {
	return &DeviceTokenRepository{db: db}
}

// Upsert registers (or re-registers, e.g. on token refresh / re-login on the
// same device) a token for a user. A token is unique across the table, so if
// the same physical device logs in as a different user, ownership moves.
func (r *DeviceTokenRepository) Upsert(ctx context.Context, req models.RegisterDeviceTokenRequest) error {
	_, err := r.db.Exec(ctx, `
		INSERT INTO device_tokens (user_id, token, platform)
		VALUES ($1, $2, $3)
		ON CONFLICT (token)
		DO UPDATE SET user_id = $1, platform = $3, updated_at = now()
	`, req.UserID, req.Token, req.Platform)
	return err
}

// GetTokensForUser returns every device token registered for a user, across
// however many devices they're logged in on.
func (r *DeviceTokenRepository) GetTokensForUser(ctx context.Context, userID string) ([]string, error) {
	rows, err := r.db.Query(ctx, `SELECT token FROM device_tokens WHERE user_id = $1`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var token string
		if err := rows.Scan(&token); err != nil {
			return nil, err
		}
		tokens = append(tokens, token)
	}
	return tokens, nil
}

// Delete removes a token, e.g. on logout so this device stops receiving pushes.
func (r *DeviceTokenRepository) Delete(ctx context.Context, token string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM device_tokens WHERE token = $1`, token)
	return err
}

// DeleteInvalid removes tokens FCM reports as unregistered/invalid, so the
// list stays clean and we stop retrying dead tokens.
func (r *DeviceTokenRepository) DeleteInvalid(ctx context.Context, tokens []string) error {
	if len(tokens) == 0 {
		return nil
	}
	_, err := r.db.Exec(ctx, `DELETE FROM device_tokens WHERE token = ANY($1)`, tokens)
	return err
}