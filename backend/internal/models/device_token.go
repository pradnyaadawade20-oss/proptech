package models

import "time"

type DeviceToken struct {
	ID        string    `json:"id"`
	UserID    string    `json:"user_id"`
	Token     string    `json:"token"`
	Platform  string    `json:"platform"` // android | ios | web
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type RegisterDeviceTokenRequest struct {
	UserID   string `json:"user_id" binding:"required"`
	Token    string `json:"token" binding:"required"`
	Platform string `json:"platform" binding:"required,oneof=android ios web"`
}

type UnregisterDeviceTokenRequest struct {
	Token string `json:"token" binding:"required"`
}