package repository

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"proptech-backend/internal/models"
)

type UserRepository struct {
	db *pgxpool.Pool
}

func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

func (r *UserRepository) GetByPhone(ctx context.Context, phone string) (*models.User, error) {
	var u models.User
	err := r.db.QueryRow(ctx, `
		SELECT id, name, phone, COALESCE(email, ''), COALESCE(avatar_url, ''), role, roles, COALESCE(active_role, role), created_at
		FROM users
		WHERE phone = $1
	`, phone).Scan(&u.ID, &u.Name, &u.Phone, &u.Email, &u.AvatarURL, &u.Role, &u.Roles, &u.ActiveRole, &u.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil // no user found, not an error
		}
		return nil, err
	}
	return &u, nil
}

func (r *UserRepository) GetByID(ctx context.Context, id string) (*models.User, error) {
	var u models.User
	err := r.db.QueryRow(ctx, `
		SELECT id, name, phone, COALESCE(email, ''), COALESCE(avatar_url, ''), role, roles, COALESCE(active_role, role), created_at
		FROM users
		WHERE id = $1
	`, id).Scan(&u.ID, &u.Name, &u.Phone, &u.Email, &u.AvatarURL, &u.Role, &u.Roles, &u.ActiveRole, &u.CreatedAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &u, nil
}

// Create matches RoleSelectionScreen's multi-select: `roles` is every role
// the person picked, `activeRole` is whichever they started with.
func (r *UserRepository) Create(ctx context.Context, name, phone, role string, roles []string) (*models.User, error) {
	if role == "" {
		role = "tenant"
	}
	if len(roles) == 0 {
		roles = []string{role}
	}
	var u models.User
	err := r.db.QueryRow(ctx, `
		INSERT INTO users (name, phone, role, roles, active_role)
		VALUES ($1, $2, $3, $4, $3)
		RETURNING id, name, phone, COALESCE(email, ''), COALESCE(avatar_url, ''), role, roles, COALESCE(active_role, role), created_at
	`, name, phone, role, roles).
		Scan(&u.ID, &u.Name, &u.Phone, &u.Email, &u.AvatarURL, &u.Role, &u.Roles, &u.ActiveRole, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// SwitchRole matches role_switcher_sheet.dart: sets the active "mode" and,
// if the account doesn't have that role yet, adds it (mirrors
// UserSession.switchTo, which calls addRole first when needed).
func (r *UserRepository) SwitchRole(ctx context.Context, id string, role string) (*models.User, error) {
	var u models.User
	err := r.db.QueryRow(ctx, `
		UPDATE users
		SET roles = CASE WHEN $1 = ANY(roles) THEN roles ELSE array_append(roles, $1) END,
		    active_role = $1,
		    role = $1
		WHERE id = $2
		RETURNING id, name, phone, COALESCE(email, ''), COALESCE(avatar_url, ''), role, roles, COALESCE(active_role, role), created_at
	`, role, id).
		Scan(&u.ID, &u.Name, &u.Phone, &u.Email, &u.AvatarURL, &u.Role, &u.Roles, &u.ActiveRole, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// UpdateProfile lets a user edit their name, email, and avatar
// (used by the Profile screen once it's wired to the backend).
func (r *UserRepository) UpdateProfile(ctx context.Context, id string, req models.UpdateProfileRequest) (*models.User, error) {
	var u models.User
	err := r.db.QueryRow(ctx, `
		UPDATE users
		SET name = $1, email = NULLIF($2, ''), avatar_url = NULLIF($3, '')
		WHERE id = $4
		RETURNING id, name, phone, COALESCE(email, ''), COALESCE(avatar_url, ''), role, roles, COALESCE(active_role, role), created_at
	`, req.Name, req.Email, req.AvatarURL, id).
		Scan(&u.ID, &u.Name, &u.Phone, &u.Email, &u.AvatarURL, &u.Role, &u.Roles, &u.ActiveRole, &u.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &u, nil
}