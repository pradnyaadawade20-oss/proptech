package repository

import (
	"context"
	"errors"
	"strings"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

// phone is nullable now (email signup doesn't collect it), so it must be
// COALESCEd or pgx fails scanning NULL into a string.
const userColumns = `id, name, COALESCE(phone, ''), COALESCE(email, ''), COALESCE(avatar_url, ''), role, roles, COALESCE(active_role, role), created_at`

func scanUser(row pgx.Row) (*models.User, error) {
	var u models.User
	if err := row.Scan(&u.ID, &u.Name, &u.Phone, &u.Email, &u.AvatarURL, &u.Role, &u.Roles, &u.ActiveRole, &u.CreatedAt); err != nil {
		return nil, err
	}
	return &u, nil
}

func normalizeEmail(email string) string {
	return strings.ToLower(strings.TrimSpace(email))
}

// GetAuthByEmail returns the user plus their password hash (empty string if
// the account has no password, e.g. an old phone-only account). Returns
// (nil, "", nil) when no such user exists.
func (r *UserRepository) GetAuthByEmail(ctx context.Context, email string) (*models.User, string, error) {
	var (
		u    models.User
		hash string
	)
	err := r.db.QueryRow(ctx, `
		SELECT `+userColumns+`, COALESCE(password_hash, '')
		FROM users
		WHERE LOWER(email) = $1
	`, normalizeEmail(email)).Scan(&u.ID, &u.Name, &u.Phone, &u.Email, &u.AvatarURL, &u.Role, &u.Roles, &u.ActiveRole, &u.CreatedAt, &hash)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, "", nil
		}
		return nil, "", err
	}
	return &u, hash, nil
}

func (r *UserRepository) GetByID(ctx context.Context, id string) (*models.User, error) {
	u, err := scanUser(r.db.QueryRow(ctx, `SELECT `+userColumns+` FROM users WHERE id = $1`, id))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return u, nil
}

// CreateWithEmail creates an email/password account (emailVerified=false only
// when the OTP step was skipped in testing mode). `roles` is every
// role the person picked, `role` is whichever they started with.
func (r *UserRepository) CreateWithEmail(ctx context.Context, name, email, passwordHash, role string, roles []string, emailVerified bool) (*models.User, error) {
	if role == "" {
		role = "tenant"
	}
	if len(roles) == 0 {
		roles = []string{role}
	}
	return scanUser(r.db.QueryRow(ctx, `
		INSERT INTO users (name, email, password_hash, email_verified, role, roles, active_role)
		VALUES ($1, $2, $3, $6, $4, $5, $4)
		RETURNING `+userColumns,
		name, normalizeEmail(email), passwordHash, role, roles, emailVerified))
}

// MarkEmailVerified is called after a successful OTP login.
func (r *UserRepository) MarkEmailVerified(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `UPDATE users SET email_verified = TRUE WHERE id = $1`, id)
	return err
}

// SwitchRole matches role_switcher_sheet.dart: sets the active "mode" and,
// if the account doesn't have that role yet, adds it (mirrors
// UserSession.switchTo, which calls addRole first when needed).
func (r *UserRepository) SwitchRole(ctx context.Context, id string, role string) (*models.User, error) {
	return scanUser(r.db.QueryRow(ctx, `
		UPDATE users
		SET roles = CASE WHEN $1 = ANY(roles) THEN roles ELSE array_append(roles, $1) END,
		    active_role = $1,
		    role = $1
		WHERE id = $2
		RETURNING `+userColumns, role, id))
}

// UpdateProfile lets a user edit their name, email, and avatar
// (used by the Profile screen once it's wired to the backend).
func (r *UserRepository) UpdateProfile(ctx context.Context, id string, req models.UpdateProfileRequest) (*models.User, error) {
	return scanUser(r.db.QueryRow(ctx, `
		UPDATE users
		SET name = $1, email = NULLIF($2, ''), avatar_url = NULLIF($3, '')
		WHERE id = $4
		RETURNING `+userColumns, req.Name, normalizeEmail(req.Email), req.AvatarURL, id))
}
