package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/notify"

	"github.com/gin-gonic/gin"
)

// GoogleLoginRequest: the Google ID token obtained by the app.
type GoogleLoginRequest struct {
	IDToken string `json:"id_token" binding:"required"`
}

type googleTokenInfo struct {
	Iss           string `json:"iss"`
	Aud           string `json:"aud"`
	Email         string `json:"email"`
	EmailVerified any    `json:"email_verified"`
	Name          string `json:"name"`
	Picture       string `json:"picture"`
}

var googleHTTP = &http.Client{Timeout: 10 * time.Second}

// googleClientIDs reads GOOGLE_CLIENT_ID (comma separated). This must be the
// Web client ID, the same one the app passes as serverClientId.
func googleClientIDs() []string {
	var ids []string
	for _, p := range strings.Split(os.Getenv("GOOGLE_CLIENT_ID"), ",") {
		if p = strings.TrimSpace(p); p != "" {
			ids = append(ids, p)
		}
	}
	return ids
}

// verifyGoogleIDToken asks Google to validate the token (signature, expiry),
// then checks audience, issuer and that the email is verified.
func verifyGoogleIDToken(ctx context.Context, idToken string, allowedAud []string) (*googleTokenInfo, error) {
	endpoint := "https://oauth2.googleapis.com/tokeninfo?id_token=" + url.QueryEscape(idToken)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	resp, err := googleHTTP.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("tokeninfo returned status %d", resp.StatusCode)
	}

	var info googleTokenInfo
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return nil, err
	}

	audOK := false
	for _, a := range allowedAud {
		if info.Aud == a {
			audOK = true
			break
		}
	}
	if !audOK {
		return nil, fmt.Errorf("token audience %q does not match GOOGLE_CLIENT_ID", info.Aud)
	}
	if info.Iss != "accounts.google.com" && info.Iss != "https://accounts.google.com" {
		return nil, fmt.Errorf("unexpected issuer %q", info.Iss)
	}
	if fmt.Sprint(info.EmailVerified) != "true" || strings.TrimSpace(info.Email) == "" {
		return nil, fmt.Errorf("google email is not verified")
	}
	return &info, nil
}

// GoogleLogin: POST /api/auth/google  {id_token}
//
// Verifies the Google ID token, then logs in the account with that email, or
// creates a passwordless one. Google has already proven email ownership, so no
// OTP is needed. Returns the same {user, token} shape as verify-otp.
func (h *AuthHandler) GoogleLogin(c *gin.Context) {
	var req GoogleLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
		return
	}

	ids := googleClientIDs()
	if len(ids) == 0 {
		log.Println("google-login: GOOGLE_CLIENT_ID is not set")
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "Google sign-in is not configured on the server"})
		return
	}

	ctx := c.Request.Context()
	info, err := verifyGoogleIDToken(ctx, req.IDToken, ids)
	if err != nil {
		log.Printf("google-login: token rejected: %v", err)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Google sign-in failed. Please try again."})
		return
	}

	email := strings.ToLower(strings.TrimSpace(info.Email))
	user, _, err := h.userRepo.GetAuthByEmail(ctx, email)
	if err != nil {
		log.Printf("google-login: lookup failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
		return
	}

	if user == nil {
		name := strings.TrimSpace(info.Name)
		if name == "" {
			name = strings.SplitN(email, "@", 2)[0]
		}
		user, err = h.userRepo.CreateWithGoogle(ctx, name, email, info.Picture)
		if err != nil {
			log.Printf("google-login: create user failed: %v", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Could not create your account. Please try again."})
			return
		}
	} else {
		_ = h.userRepo.MarkEmailVerified(ctx, user.ID)
	}

	token, err := middleware.GenerateToken(user.ID, user.Email, user.Role)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	notify.SendLater(6*time.Second, user.ID, "account", "New login", "You just signed in to PropTech.")

	c.JSON(http.StatusOK, gin.H{
		"user":  user,
		"token": token,
	})
}
