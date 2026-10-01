package repository

import (
	"context"
	"errors"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

// ErrNotificationNotFound: no such notification for this user.
var ErrNotificationNotFound = errors.New("notification not found")

type NotificationRepository struct {
	db *pgxpool.Pool
}

func NewNotificationRepository(db *pgxpool.Pool) *NotificationRepository {
	return &NotificationRepository{db: db}
}

const notificationSelectQuery = `
	SELECT id, user_id, type, title, body, route, is_read, created_at
	FROM notifications
`

func scanNotification(row interface {
	Scan(dest ...any) error
}) (*models.Notification, error) {
	var n models.Notification
	err := row.Scan(&n.ID, &n.UserID, &n.Type, &n.Title, &n.Body, &n.Route, &n.IsRead, &n.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &n, nil
}

// GetByUserID returns all notifications for a user, newest first.
func (r *NotificationRepository) GetByUserID(ctx context.Context, userID string) ([]models.Notification, error) {
	rows, err := r.db.Query(ctx, notificationSelectQuery+` WHERE user_id = $1 ORDER BY created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	notifications := []models.Notification{}
	for rows.Next() {
		n, err := scanNotification(rows)
		if err != nil {
			return nil, err
		}
		notifications = append(notifications, *n)
	}
	return notifications, nil
}

func (r *NotificationRepository) GetByID(ctx context.Context, id string) (*models.Notification, error) {
	row := r.db.QueryRow(ctx, notificationSelectQuery+` WHERE id = $1`, id)
	return scanNotification(row)
}

func (r *NotificationRepository) Create(ctx context.Context, req models.CreateNotificationRequest) (*models.Notification, error) {
	var id string
	err := r.db.QueryRow(ctx, `
		INSERT INTO notifications (user_id, type, title, body, route)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`, req.UserID, req.Type, req.Title, req.Body, req.Route).Scan(&id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

// MarkRead marks a single notification as read — only if it belongs to userID.
func (r *NotificationRepository) MarkRead(ctx context.Context, id, userID string) (*models.Notification, error) {
	tag, err := r.db.Exec(ctx, `UPDATE notifications SET is_read = TRUE WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrNotificationNotFound
	}
	return r.GetByID(ctx, id)
}

// MarkAllRead marks every notification for a user as read.
func (r *NotificationRepository) MarkAllRead(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx, `UPDATE notifications SET is_read = TRUE WHERE user_id = $1 AND is_read = FALSE`, userID)
	return err
}

// Delete removes a notification — only if it belongs to userID.
func (r *NotificationRepository) Delete(ctx context.Context, id, userID string) error {
	tag, err := r.db.Exec(ctx, `DELETE FROM notifications WHERE id = $1 AND user_id = $2`, id, userID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotificationNotFound
	}
	return nil
}
