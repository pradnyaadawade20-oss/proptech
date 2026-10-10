package repository

import (
	"context"
	"errors"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
)

// SaveAvatar stores the photo bytes and points avatar_url at the serving route.
func (r *UserRepository) SaveAvatar(ctx context.Context, id string, data []byte, contentType, avatarURL string) (*models.User, error) {
	return scanUser(r.db.QueryRow(ctx, `
		UPDATE users
		SET avatar_data = $1, avatar_content_type = $2, avatar_url = $3
		WHERE id = $4
		RETURNING `+userColumns, data, contentType, avatarURL, id))
}

// GetAvatar returns (nil, "", nil) when the user has no uploaded photo.
func (r *UserRepository) GetAvatar(ctx context.Context, id string) ([]byte, string, error) {
	var (
		data []byte
		ct   *string
	)
	err := r.db.QueryRow(ctx,
		`SELECT avatar_data, avatar_content_type FROM users WHERE id = $1`, id,
	).Scan(&data, &ct)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, "", nil
		}
		return nil, "", err
	}
	if ct == nil || *ct == "" {
		return data, "image/jpeg", nil
	}
	return data, *ct, nil
}

// ClearAvatar removes the uploaded photo (and any avatar_url, e.g. a Google one).
func (r *UserRepository) ClearAvatar(ctx context.Context, id string) (*models.User, error) {
	return scanUser(r.db.QueryRow(ctx, `
		UPDATE users
		SET avatar_data = NULL, avatar_content_type = NULL, avatar_url = NULL
		WHERE id = $1
		RETURNING `+userColumns, id))
}