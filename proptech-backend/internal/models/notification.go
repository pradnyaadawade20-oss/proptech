package models

import "time"

type Notification struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Type      string    `json:"type"` // property | visit | agreement | message | account
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	Route     string    `json:"route"`
	IsRead    bool      `json:"is_read"`
	CreatedAt time.Time `json:"created_at"`
}

type CreateNotificationRequest struct {
	UserID string `json:"user_id" binding:"required"`
	Type   string `json:"type" binding:"required,oneof=property visit agreement message account"`
	Title  string `json:"title" binding:"required"`
	Body   string `json:"body" binding:"required"`
	Route  string `json:"route"`
}
