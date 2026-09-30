package notify

import (
	"context"
	"log"
	"strings"
	"time"

	"proptech-backend/internal/models"
	"proptech-backend/internal/push"
	"proptech-backend/internal/repository"

	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	db        *pgxpool.Pool
	notifRepo *repository.NotificationRepository
	tokenRepo *repository.DeviceTokenRepository
	sender    *push.Sender // nil when Firebase is not configured
)

// Init is called once from main.go.
func Init(pool *pgxpool.Pool, n *repository.NotificationRepository, t *repository.DeviceTokenRepository, s *push.Sender) {
	db, notifRepo, tokenRepo, sender = pool, n, t, s
}

// Send stores a notification for the user and pushes it to all their devices.
func Send(userID, typ, title, body string) {
	go send(userID, typ, title, body)
}

// SendLater is like Send but waits first. Used for login alerts so that the
// device has time to register its FCM token right after logging in.
func SendLater(delay time.Duration, userID, typ, title, body string) {
	go func() {
		time.Sleep(delay)
		send(userID, typ, title, body)
	}()
}

// NewMessage notifies the receiver of a chat message.
func NewMessage(senderID, receiverID, text string) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		name := userName(ctx, senderID)
		if name == "" {
			name = "Someone"
		}
		send(receiverID, "message", "New message from "+name, truncate(text, 120))
	}()
}

// BroadcastExcept notifies every user except one (e.g. a new listing).
func BroadcastExcept(exceptUserID, typ, title, body string) {
	go func() {
		if db == nil {
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		rows, err := db.Query(ctx, `SELECT id::text FROM users WHERE id::text <> $1 LIMIT 1000`, exceptUserID)
		if err != nil {
			cancel()
			log.Println("notify: broadcast query failed:", err)
			return
		}
		var ids []string
		for rows.Next() {
			var id string
			if rows.Scan(&id) == nil {
				ids = append(ids, id)
			}
		}
		rows.Close()
		cancel()
		for _, id := range ids {
			send(id, typ, title, body)
		}
	}()
}

// UserName returns the display name of a user ("" if unknown).
func UserName(userID string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return userName(ctx, userID)
}

func userName(ctx context.Context, userID string) string {
	if db == nil || userID == "" {
		return ""
	}
	var name string
	if err := db.QueryRow(ctx, `SELECT name FROM users WHERE id::text = $1`, userID).Scan(&name); err != nil {
		return ""
	}
	return strings.TrimSpace(name)
}

func send(userID, typ, title, body string) {
	if userID == "" || notifRepo == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	n, err := notifRepo.Create(ctx, models.CreateNotificationRequest{
		UserID: userID, Type: typ, Title: title, Body: body,
	})
	if err != nil {
		log.Println("notify: create failed:", err)
		return
	}
	if sender == nil || tokenRepo == nil {
		return // Firebase not configured: in-app notification only
	}
	tokens, err := tokenRepo.GetTokensForUser(ctx, userID)
	if err != nil || len(tokens) == 0 {
		return
	}
	invalid := sender.SendToTokens(ctx, tokens, title, body, map[string]string{
		"type":            typ,
		"notification_id": n.ID,
	})
	if len(invalid) > 0 {
		_ = tokenRepo.DeleteInvalid(ctx, invalid)
	}
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}