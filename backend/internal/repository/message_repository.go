package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"proptech-backend/internal/models"
)

type MessageRepository struct {
	db *pgxpool.Pool
}

func NewMessageRepository(db *pgxpool.Pool) *MessageRepository {
	return &MessageRepository{db: db}
}

func (r *MessageRepository) Send(ctx context.Context, req models.SendMessageRequest) (*models.Message, error) {
	var m models.Message
	err := r.db.QueryRow(ctx, `
		INSERT INTO messages (sender_id, receiver_id, property_id, text)
		VALUES ($1, $2, $3, $4)
		RETURNING id, sender_id, receiver_id, property_id, text, is_read, sent_at
	`, req.SenderID, req.ReceiverID, req.PropertyID, req.Text).
		Scan(&m.ID, &m.SenderID, &m.ReceiverID, &m.PropertyID, &m.Text, &m.IsRead, &m.SentAt)
	if err != nil {
		return nil, err
	}
	m.IsMe = true // sender always sees their own just-sent message as "me"
	return &m, nil
}

// GetConversations returns one row per other user the current user has
// exchanged messages with, with the latest message and unread count —
// matches the frontend ChatConversation model used by the chat list screen.
func (r *MessageRepository) GetConversations(ctx context.Context, userID string) ([]models.ChatConversation, error) {
	rows, err := r.db.Query(ctx, `
		WITH conversation_partners AS (
			SELECT DISTINCT
				CASE WHEN sender_id = $1 THEN receiver_id ELSE sender_id END AS other_user_id
			FROM messages
			WHERE sender_id = $1 OR receiver_id = $1
		),
		last_messages AS (
			SELECT DISTINCT ON (other_user_id)
				cp.other_user_id,
				m.text AS last_message,
				m.sent_at AS last_message_time
			FROM conversation_partners cp
			JOIN messages m
				ON (m.sender_id = $1 AND m.receiver_id = cp.other_user_id)
				OR (m.receiver_id = $1 AND m.sender_id = cp.other_user_id)
			ORDER BY cp.other_user_id, m.sent_at DESC
		),
		unread_counts AS (
			SELECT sender_id AS other_user_id, COUNT(*) AS unread_count
			FROM messages
			WHERE receiver_id = $1 AND is_read = FALSE
			GROUP BY sender_id
		)
		SELECT u.id, u.name, COALESCE(u.avatar_url, ''), lm.last_message, lm.last_message_time,
		       COALESCE(uc.unread_count, 0)
		FROM last_messages lm
		JOIN users u ON u.id = lm.other_user_id
		LEFT JOIN unread_counts uc ON uc.other_user_id = lm.other_user_id
		ORDER BY lm.last_message_time DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var conversations []models.ChatConversation
	for rows.Next() {
		var conv models.ChatConversation
		err := rows.Scan(&conv.ID, &conv.Name, &conv.AvatarURL, &conv.LastMessage, &conv.LastMessageTime, &conv.UnreadCount)
		if err != nil {
			return nil, err
		}
		conversations = append(conversations, conv)
	}
	return conversations, nil
}

// GetMessagesWith returns the full message thread between the current user
// and another user, oldest first, with IsMe derived per-message.
func (r *MessageRepository) GetMessagesWith(ctx context.Context, userID string, otherUserID string) ([]models.Message, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, sender_id, receiver_id, property_id, text, is_read, sent_at
		FROM messages
		WHERE (sender_id = $1 AND receiver_id = $2) OR (sender_id = $2 AND receiver_id = $1)
		ORDER BY sent_at ASC
	`, userID, otherUserID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []models.Message
	for rows.Next() {
		var m models.Message
		err := rows.Scan(&m.ID, &m.SenderID, &m.ReceiverID, &m.PropertyID, &m.Text, &m.IsRead, &m.SentAt)
		if err != nil {
			return nil, err
		}
		m.IsMe = m.SenderID == userID
		messages = append(messages, m)
	}
	return messages, nil
}

// MarkRead marks all messages from otherUserID to userID as read
// (call this when the user opens that chat thread).
func (r *MessageRepository) MarkRead(ctx context.Context, userID string, otherUserID string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE messages SET is_read = TRUE
		WHERE receiver_id = $1 AND sender_id = $2 AND is_read = FALSE
	`, userID, otherUserID)
	return err
}