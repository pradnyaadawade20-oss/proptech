package config

import (
	"bytes"
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

type Config struct {
	Port                string
	AppEnv              string
	DBHost              string
	DBPort              string
	DBUser              string
	DBPassword          string
	DBName              string
	DBSSLMode           string
	JWTSecret           string
	FirebaseCredentials string

	// Email (OTP) — see internal/mail
	SMTPHost    string
	SMTPPort    string
	SMTPUser    string
	SMTPPass    string
	BrevoAPIKey string
	EmailFrom   string
	EmailName   string
	DevLogOTP   bool

	// Testing only: lets the app skip the OTP step (see AuthHandler.SkipOTP).
	DevSkipOTP bool
}

// LoadDotEnv loads a .env file into the process environment. Unlike a plain
// godotenv.Load() it:
//   - strips a UTF-8 BOM (Windows editors add one, which turns the first key
//     into "\ufeffPORT" so that variable silently never loads),
//   - looks in the current folder and up to two parents, so it still works if
//     the server is started from cmd/server,
//   - never overrides variables already set in the real environment (Render etc.).
func LoadDotEnv() {
	for _, dir := range []string{".", "..", filepath.Join("..", "..")} {
		path := filepath.Join(dir, ".env")
		raw, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		raw = bytes.TrimPrefix(raw, []byte{0xEF, 0xBB, 0xBF})
		vars, err := godotenv.Parse(bytes.NewReader(raw))
		if err != nil {
			log.Printf("Could not parse %s: %v", path, err)
			return
		}
		loaded := 0
		for k, v := range vars {
			k = strings.TrimSpace(k)
			if k == "" {
				continue
			}
			if _, exists := os.LookupEnv(k); !exists {
				_ = os.Setenv(k, strings.TrimSpace(v))
				loaded++
			}
		}
		log.Printf("Loaded %d variable(s) from %s", loaded, path)
		return
	}
	log.Println("No .env file found, using system environment variables")
}

// EmailTransport describes which OTP email transport is active, for the
// startup log — so a misconfigured .env is obvious immediately.
func (c *Config) EmailTransport() string {
	switch {
	case c.BrevoAPIKey != "":
		return "Brevo HTTPS API (from: " + c.EmailFrom + ")"
	case c.SMTPHost != "":
		return "SMTP " + c.SMTPHost + ":" + c.SMTPPort + " (user: " + c.SMTPUser + ", from: " + c.EmailFrom + ")"
	case c.DevLogOTP:
		return "NOT CONFIGURED — dev mode: OTP will be printed in this log"
	default:
		return "NOT CONFIGURED — set SMTP_HOST or BREVO_API_KEY (OTP emails will fail)"
	}
}

func LoadConfig() *Config {
	cfg := loadConfig()
	// Gmail shows app passwords as "abcd efgh ijkl mnop"; the spaces are not part of it.
	if strings.Contains(cfg.SMTPHost, "gmail.com") {
		cfg.SMTPPass = strings.ReplaceAll(cfg.SMTPPass, " ", "")
	}
	return cfg
}

func loadConfig() *Config {
	return &Config{
		Port:                getEnv("PORT", "8080"),
		AppEnv:              getEnv("APP_ENV", "development"),
		DBHost:              getEnv("DB_HOST", "localhost"),
		DBPort:              getEnv("DB_PORT", "5432"),
		DBUser:              getEnv("DB_USER", "postgres"),
		DBPassword:          getEnv("DB_PASSWORD", "postgres"),
		DBName:              getEnv("DB_NAME", "proptech_db"),
		DBSSLMode:           getEnv("DB_SSLMODE", "disable"),
		JWTSecret:           getEnv("JWT_SECRET", ""),
		FirebaseCredentials: getEnv("FIREBASE_CREDENTIALS_FILE", "firebase-service-account.json"),

		SMTPHost:    getEnv("SMTP_HOST", ""),
		SMTPPort:    getEnv("SMTP_PORT", "587"),
		SMTPUser:    getEnv("SMTP_USER", ""),
		SMTPPass:    getEnv("SMTP_PASS", ""),
		BrevoAPIKey: getEnv("BREVO_API_KEY", ""),
		EmailFrom:   getEnv("EMAIL_FROM", ""),
		EmailName:   getEnv("EMAIL_FROM_NAME", "PropTech"),
		DevLogOTP:   getEnv("DEV_LOG_OTP", "") == "true",
		DevSkipOTP:  getEnv("DEV_SKIP_OTP", "") == "true",
	}
}

func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return strings.TrimSpace(value)
	}
	return fallback
}

func (c *Config) DBConnString() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=%s",
		c.DBUser, c.DBPassword, c.DBHost, c.DBPort, c.DBName, c.DBSSLMode,
	)
}

func NewDBPool(cfg *Config) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(context.Background(), cfg.DBConnString())
	if err != nil {
		return nil, err
	}

	if err := pool.Ping(context.Background()); err != nil {
		return nil, err
	}

	return pool, nil
}
