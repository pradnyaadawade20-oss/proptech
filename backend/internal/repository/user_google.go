package repository

import (
	"context"

	"proptech-backend/internal/models"
)

// CreateWithGoogle creates a passwordless account for an email that Google
// has already verified. Same defaults as CreateWithEmail (role "tenant").
func (r *UserRepository) CreateWithGoogle(ctx context.Context, name, email, avatarURL string) (*models.User, error) {
	roles := []string{"tenant"}
	return scanUser(r.db.QueryRow(ctx, `
		INSERT INTO users (name, email, email_verified, avatar_url, role, roles, active_role)
		VALUES ($1, $2, TRUE, NULLIF($3, ''), $4, $5, $4)
		RETURNING `+userColumns,
		name, normalizeEmail(email), avatarURL, "tenant", roles))
}