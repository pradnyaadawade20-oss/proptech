package push

import (
	"context"
	"log"

	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"google.golang.org/api/option"
)

// Sender wraps the Firebase Admin SDK messaging client so the rest of the
// backend can send a push without knowing about Firebase credentials.
type Sender struct {
	client *messaging.Client
}

// NewSender initializes the Firebase Admin app from a service account JSON
// file (downloaded from Firebase Console -> Project Settings -> Service
// Accounts -> Generate new private key). Path comes from
// FIREBASE_CREDENTIALS_FILE (see internal/config).
//
// If the file is missing, NewSender returns (nil, err) — callers should log
// the error and continue running without push (so local dev without Firebase
// set up doesn't crash the whole server).
func NewSender(ctx context.Context, credentialsFile string) (*Sender, error) {
	app, err := firebase.NewApp(ctx, nil, option.WithCredentialsFile(credentialsFile))
	if err != nil {
		return nil, err
	}

	client, err := app.Messaging(ctx)
	if err != nil {
		return nil, err
	}

	return &Sender{client: client}, nil
}

// SendToTokens sends the same notification to every token in the list
// (typically all of one user's devices). It returns the tokens FCM reports
// as invalid/unregistered, so the caller can clean them up.
func (s *Sender) SendToTokens(ctx context.Context, tokens []string, title, body string, data map[string]string) (invalidTokens []string) {
	if s == nil || len(tokens) == 0 {
		return nil
	}

	message := &messaging.MulticastMessage{
		Tokens: tokens,
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Data: data,
		Android: &messaging.AndroidConfig{
			Priority: "high",
		},
		APNS: &messaging.APNSConfig{
			Payload: &messaging.APNSPayload{
				Aps: &messaging.Aps{Sound: "default"},
			},
		},
	}

	response, err := s.client.SendEachForMulticast(ctx, message)
	if err != nil {
		log.Println("fcm: send failed:", err)
		return nil
	}

	for i, resp := range response.Responses {
		if !resp.Success && messaging.IsRegistrationTokenNotRegistered(resp.Error) {
			invalidTokens = append(invalidTokens, tokens[i])
		}
	}
	return invalidTokens
}