// Package relay connects a buyer to an owner WITHOUT showing either number.
//
//	RELAY_WEBHOOK_URL    your telephony bridge (Exotel / Twilio / Knowlarity ...).
//	                     We POST {lead_id, buyer_phone, owner_phone}; the bridge
//	                     calls both people and joins them. Numbers never go to the app.
//	RELAY_WEBHOOK_TOKEN  optional bearer token for that webhook.
//
// Without RELAY_WEBHOOK_URL the "callback" mode is used: the owner gets a push
// notification and calls the buyer back from the Leads screen.
package relay

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

type Request struct {
	LeadID     string `json:"lead_id"`
	BuyerPhone string `json:"buyer_phone"`
	OwnerPhone string `json:"owner_phone"`
}

type Provider interface {
	Name() string // "relay" | "callback"
	Connect(ctx context.Context, r Request) error
}

type callback struct{}

func (callback) Name() string                          { return "callback" }
func (callback) Connect(context.Context, Request) error { return nil }

type webhook struct {
	url, token string
	client     *http.Client
}

func (webhook) Name() string { return "relay" }

func (w webhook) Connect(ctx context.Context, r Request) error {
	body, _ := json.Marshal(r)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, w.url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if w.token != "" {
		req.Header.Set("Authorization", "Bearer "+w.token)
	}
	resp, err := w.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return fmt.Errorf("relay webhook returned %d", resp.StatusCode)
	}
	return nil
}

func FromEnv() Provider {
	u := strings.TrimSpace(os.Getenv("RELAY_WEBHOOK_URL"))
	if u == "" {
		return callback{}
	}
	return webhook{url: u, token: strings.TrimSpace(os.Getenv("RELAY_WEBHOOK_TOKEN")), client: &http.Client{Timeout: 10 * time.Second}}
}