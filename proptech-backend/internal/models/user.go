package models

import "time"

// Roles is a multi-role account like the frontend's UserSession —
// someone can be a Buyer/Tenant AND an Owner AND a Broker on one account,
// and ActiveRole is whichever "mode" they're currently in.
type User struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	Phone      string    `json:"phone"`
	Email      string    `json:"email"`
	AvatarURL  string    `json:"avatar_url"`
	Role       string    `json:"role"` // deprecated: kept for backward compat, mirrors ActiveRole
	Roles      []string  `json:"roles"`
	ActiveRole string    `json:"active_role"`
	CreatedAt  time.Time `json:"created_at"`
}

type SendOTPRequest struct {
	Phone string `json:"phone" binding:"required"`
}

type VerifyOTPRequest struct {
	Phone string   `json:"phone" binding:"required"`
	Name  string   `json:"name" binding:"required"`
	OTP   string   `json:"otp" binding:"required"`
	Role  string   `json:"role"`  // optional, defaults to "tenant"; kept for single-role callers
	Roles []string `json:"roles"` // optional — matches RoleSelectionScreen's multi-select ("Continue with N roles")
}

// SwitchRoleRequest matches role_switcher_sheet.dart — picking a role the
// account already has, or adding a new one on the spot.
type SwitchRoleRequest struct {
	Role string `json:"role" binding:"required,oneof=buyer_tenant owner broker"`
}

// UpdateProfileRequest is used by the Profile screen to edit name/email/avatar
// (matches the fields shown there, e.g. name and email).
type UpdateProfileRequest struct {
	Name      string `json:"name" binding:"required"`
	Email     string `json:"email"`
	AvatarURL string `json:"avatar_url"`
}