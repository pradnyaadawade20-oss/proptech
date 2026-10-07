// Package mail sends transactional email (OTP codes).
//
// Two transports, picked automatically from env vars:
//   - Brevo HTTPS API  (if BREVO_API_KEY is set)  -> works on Render free tier
//   - SMTP             (if SMTP_HOST is set)      -> Gmail / Brevo SMTP / etc.
//
// Render's free web services block outbound SMTP ports 25/465/587, so on
// Render free use the Brevo API. SMTP works locally and on paid hosts.
package mail

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/smtp"
	"strings"
	"time"
)

type Config struct {
	// SMTP
	Host     string
	Port     string // "587" (STARTTLS) or "465" (implicit TLS)
	Username string
	Password string

	// Brevo HTTPS API
	BrevoAPIKey string

	// Shared
	FromEmail string
	FromName  string

	// If true and no transport is configured, the OTP is printed to the
	// server log instead of failing. Local development only.
	DevLogOTP bool
}

type Mailer struct {
	cfg Config
}

func New(cfg Config) *Mailer {
	if cfg.Port == "" {
		cfg.Port = "587"
	}
	if cfg.FromEmail == "" {
		cfg.FromEmail = cfg.Username
	}
	if cfg.FromName == "" {
		cfg.FromName = "PropTech"
	}
	return &Mailer{cfg: cfg}
}

// SendOTP emails a login code to `to`.
func (m *Mailer) SendOTP(ctx context.Context, to, otp string) error {
	subject := "Your PropTech verification code"
	text := fmt.Sprintf(
		"Your PropTech verification code is %s.\n\nIt expires in 10 minutes. If you didn't request this, you can ignore this email.",
		otp,
	)
	html := fmt.Sprintf(
		`<div style="font-family:Arial,sans-serif;max-width:420px;margin:auto">`+
			`<h2>Verify your email</h2>`+
			`<p>Your PropTech verification code is:</p>`+
			`<p style="font-size:32px;letter-spacing:8px;font-weight:bold">%s</p>`+
			`<p style="color:#666">It expires in 10 minutes. If you didn't request this, you can ignore this email.</p>`+
			`</div>`, otp,
	)

	switch {
	case m.cfg.BrevoAPIKey != "":
		return m.sendBrevo(ctx, to, subject, html, text)
	case m.cfg.Host != "":
		return m.sendSMTP(ctx, to, subject, text)
	case m.cfg.DevLogOTP:
		log.Printf("[DEV] email not configured — OTP for %s is %s", to, otp)
		return nil
	default:
		return errors.New("email is not configured (set SMTP_HOST or BREVO_API_KEY)")
	}
}

// ---- Brevo HTTPS API -------------------------------------------------------

func (m *Mailer) sendBrevo(ctx context.Context, to, subject, html, text string) error {
	body, _ := json.Marshal(map[string]any{
		"sender":      map[string]string{"name": m.cfg.FromName, "email": m.cfg.FromEmail},
		"to":          []map[string]string{{"email": to}},
		"subject":     subject,
		"htmlContent": html,
		"textContent": text,
	})

	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, "https://api.brevo.com/v3/smtp/email", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("api-key", m.cfg.BrevoAPIKey)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("brevo request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("brevo returned %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}
	return nil
}

// ---- SMTP ------------------------------------------------------------------

func (m *Mailer) sendSMTP(ctx context.Context, to, subject, text string) error {
	addr := net.JoinHostPort(m.cfg.Host, m.cfg.Port)
	dialer := &net.Dialer{Timeout: 10 * time.Second}

	var conn net.Conn
	var err error
	if m.cfg.Port == "465" {
		conn, err = tls.DialWithDialer(dialer, "tcp", addr, &tls.Config{ServerName: m.cfg.Host})
	} else {
		conn, err = dialer.DialContext(ctx, "tcp", addr)
	}
	if err != nil {
		return fmt.Errorf("smtp connect %s: %w", addr, err)
	}
	// Hard deadline for the whole SMTP conversation.
	_ = conn.SetDeadline(time.Now().Add(20 * time.Second))

	c, err := smtp.NewClient(conn, m.cfg.Host)
	if err != nil {
		conn.Close()
		return fmt.Errorf("smtp handshake: %w", err)
	}
	defer c.Close()

	if m.cfg.Port != "465" {
		if ok, _ := c.Extension("STARTTLS"); !ok {
			return errors.New("smtp server does not support STARTTLS")
		}
		if err := c.StartTLS(&tls.Config{ServerName: m.cfg.Host}); err != nil {
			return fmt.Errorf("smtp starttls: %w", err)
		}
	}

	if m.cfg.Username != "" {
		if err := c.Auth(smtp.PlainAuth("", m.cfg.Username, m.cfg.Password, m.cfg.Host)); err != nil {
			return fmt.Errorf("smtp auth: %w", err)
		}
	}

	if err := c.Mail(m.cfg.FromEmail); err != nil {
		return fmt.Errorf("smtp MAIL FROM: %w", err)
	}
	if err := c.Rcpt(to); err != nil {
		return fmt.Errorf("smtp RCPT TO: %w", err)
	}
	w, err := c.Data()
	if err != nil {
		return fmt.Errorf("smtp DATA: %w", err)
	}

	// `to` was validated as an email by the request binding, so it cannot
	// contain CR/LF; strip anyway as defence in depth against header injection.
	clean := func(s string) string { return strings.NewReplacer("\r", "", "\n", "").Replace(s) }
	msg := "From: " + clean(m.cfg.FromName) + " <" + clean(m.cfg.FromEmail) + ">\r\n" +
		"To: " + clean(to) + "\r\n" +
		"Subject: " + subject + "\r\n" +
		"Date: " + time.Now().Format(time.RFC1123Z) + "\r\n" +
		"MIME-Version: 1.0\r\n" +
		"Content-Type: text/plain; charset=UTF-8\r\n\r\n" +
		text + "\r\n"
	if _, err := w.Write([]byte(msg)); err != nil {
		return fmt.Errorf("smtp write: %w", err)
	}
	if err := w.Close(); err != nil {
		return fmt.Errorf("smtp send: %w", err)
	}
	return c.Quit()
}

// SendPasswordReset emails a password-reset code to `to`.
func (m *Mailer) SendPasswordReset(ctx context.Context, to, otp string) error {
	subject := "Reset your PropTech password"
	text := fmt.Sprintf(
		"Your PropTech password reset code is %s.\n\nIt expires in 10 minutes. If you didn't request this, you can ignore this email — your password will not change.",
		otp,
	)
	html := fmt.Sprintf(
		`<div style="font-family:Arial,sans-serif;max-width:420px;margin:auto">`+
			`<h2>Reset your password</h2>`+
			`<p>Your PropTech password reset code is:</p>`+
			`<p style="font-size:32px;letter-spacing:8px;font-weight:bold">%s</p>`+
			`<p style="color:#666">It expires in 10 minutes. If you didn't request this, you can ignore this email — your password will not change.</p>`+
			`</div>`, otp,
	)

	switch {
	case m.cfg.BrevoAPIKey != "":
		return m.sendBrevo(ctx, to, subject, html, text)
	case m.cfg.Host != "":
		return m.sendSMTP(ctx, to, subject, text)
	case m.cfg.DevLogOTP:
		log.Printf("[DEV] email not configured — password reset code for %s is %s", to, otp)
		return nil
	default:
		return errors.New("email is not configured (set SMTP_HOST or BREVO_API_KEY)")
	}
}