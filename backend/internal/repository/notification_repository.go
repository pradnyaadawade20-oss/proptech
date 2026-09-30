package repository

import (
	"context"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

type NotificationRepository struct {
	db *pgxpool.Pool
}

func NewNotificationRepository(db *pgxpool.Pool) *NotificationRepository {
	return &NotificationRepository{db: db}
}

const notificationSelectQuery = `
	SELECT id, user_id, type, title, body, is_read, created_at
	FROM notifications
`

func scanNotification(row interface {
	Scan(dest ...any) error
}) (*models.Notification, error) {
	var n models.Notification
	err := row.Scan(&n.ID, &n.UserID, &n.Type, &n.Title, &n.Body, &n.IsRead, &n.CreatedAt)
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
		INSERT INTO notifications (user_id, type, title, body)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`, req.UserID, req.Type, req.Title, req.Body).Scan(&id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

// MarkRead marks a single notification as read.
func (r *NotificationRepository) MarkRead(ctx context.Context, id string) (*models.Notification, error) {
	_, err := r.db.Exec(ctx, `UPDATE notifications SET is_read = TRUE WHERE id = $1`, id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

// MarkAllRead marks every notification for a user as read.
func (r *NotificationRepository) MarkAllRead(ctx context.Context, userID string) error {
	_, err := r.db.Exec(ctx, `UPDATE notifications SET is_read = TRUE WHERE user_id = $1 AND is_read = FALSE`, userID)
	return err
}

func (r *NotificationRepository) Delete(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM notifications WHERE id = $1`, id)
	return err
}
