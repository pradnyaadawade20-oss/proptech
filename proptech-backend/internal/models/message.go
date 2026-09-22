package models

import "time"

type Message struct {
	ID         string    `json:"id"`
	SenderID   string    `json:"sender_id"`
	ReceiverID string    `json:"receiver_id"`
	PropertyID *string   `json:"property_id,omitempty"`
	Text       string    `json:"text"`
	IsMe       bool      `json:"is_me"` // derived: sender_id == requesting user
	IsRead     bool      `json:"is_read"`
	SentAt     time.Time `json:"sent_at"`
}

type SendMessageRequest struct {
	SenderID   string  `json:"sender_id" binding:"required"`
	ReceiverID string  `json:"receiver_id" binding:"required"`
	PropertyID *string `json:"property_id"`
	Text       string  `json:"text" binding:"required"`
}

// ChatConversation is a derived/aggregated view: one row per other user
// the current user has exchanged messages with, matching the frontend
// ChatConversation model (name, avatar, last message, unread count).
type ChatConversation struct {
	ID              string    `json:"id"` // the other user's ID
	Name            string    `json:"name"`
	AvatarURL       string    `json:"avatar_url"`
	LastMessage     string    `json:"last_message"`
	LastMessageTime time.Time `json:"last_message_time"`
	UnreadCount     int       `json:"unread_count"`
}