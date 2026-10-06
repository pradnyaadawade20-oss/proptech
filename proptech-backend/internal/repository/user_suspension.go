package repository

import "context"

// IsSuspended reports whether an admin has suspended this user.
func (r *UserRepository) IsSuspended(ctx context.Context, id string) (bool, error) {
	var s bool
	err := r.db.QueryRow(ctx,
		`SELECT suspended_at IS NOT NULL FROM users WHERE id = $1::uuid`, id).Scan(&s)
	return s, err
}