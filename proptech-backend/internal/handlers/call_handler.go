package handlers

import (
	"context"
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"proptech-backend/internal/middleware"
	"proptech-backend/internal/models"
	"proptech-backend/internal/notify"
	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

// Audio calls: WebRTC media goes phone <-> phone; this handler only does
// signaling (offer / answer / ICE) over a WebSocket, plus call state in the DB.
//
// Flow:
//  1. caller  POST /api/calls {lead_id | property_id[,peer_id]}  -> call row (ringing) + ICE servers;
//     callee gets a WS "incoming" event AND a push (dedupe on call_id).
//  2. callee  WS {type:"accept", call_id} -> caller gets "accepted".
//  3. caller  WS {type:"offer", data}  -> callee;  callee WS "answer" -> caller;
//     both send "ice" candidates.
//  4. either  WS {type:"end"}  (callee may also {type:"reject"} or POST /reject).
//
// The hub is in memory: it works for ONE server instance. Running several
// instances needs a shared pub/sub (e.g. Redis) in front of sendTo.

const (
	ringTimeout = 45 * time.Second
	pongWait    = 60 * time.Second
	pingEvery   = 25 * time.Second
	writeWait   = 10 * time.Second
)

type signalMsg struct {
	Type   string          `json:"type"`
	CallID string          `json:"call_id,omitempty"`
	From   string          `json:"from,omitempty"`
	Reason string          `json:"reason,omitempty"`
	Data   json.RawMessage `json:"data,omitempty"`
}

func errMsg(callID, text string) signalMsg {
	return signalMsg{Type: "error", CallID: callID, Reason: text}
}

func mustJSON(v any) json.RawMessage {
	b, err := json.Marshal(v)
	if err != nil {
		return nil
	}
	return b
}

// ---------------------------------------------------------------- hub

type callConn struct {
	userID string
	ws     *websocket.Conn
	send   chan []byte
}

type callHub struct {
	mu    sync.RWMutex
	conns map[string]*callConn // one live socket per user
}

func newCallHub() *callHub { return &callHub{conns: map[string]*callConn{}} }

func (h *callHub) register(c *callConn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if old, ok := h.conns[c.userID]; ok {
		close(old.send) // old socket's writer closes it
	}
	h.conns[c.userID] = c
}

// unregister reports whether c was still the registered socket (false = the
// user already reconnected on a newer socket).
func (h *callHub) unregister(c *callConn) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	if cur, ok := h.conns[c.userID]; ok && cur == c {
		delete(h.conns, c.userID)
		close(c.send)
		return true
	}
	return false
}

func (h *callHub) sendTo(userID string, v any) bool {
	b, err := json.Marshal(v)
	if err != nil {
		return false
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	c, ok := h.conns[userID]
	if !ok {
		return false
	}
	select {
	case c.send <- b:
		return true
	default:
		return false // slow client: drop rather than block signaling
	}
}

func (c *callConn) writePump() {
	t := time.NewTicker(pingEvery)
	defer t.Stop()
	defer c.ws.Close()
	for {
		select {
		case b, ok := <-c.send:
			_ = c.ws.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				_ = c.ws.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.ws.WriteMessage(websocket.TextMessage, b); err != nil {
				return
			}
		case <-t.C:
			_ = c.ws.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.ws.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

// ---------------------------------------------------------------- handler

type CallHandler struct {
	repo *repository.CallRepository
	hub  *callHub
}

func NewCallHandler(repo *repository.CallRepository) *CallHandler {
	return &CallHandler{repo: repo, hub: newCallHub()}
}

var callUpgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	// Native apps send no Origin header; browsers do - refuse those.
	CheckOrigin: func(r *http.Request) bool { return r.Header.Get("Origin") == "" },
}

func writeCallError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, repository.ErrCallForbidden):
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error(), "code": "forbidden"})
	case errors.Is(err, repository.ErrOwnerLocked):
		c.JSON(http.StatusForbidden, gin.H{"error": err.Error(), "code": "owner_locked"})
	case errors.Is(err, repository.ErrCallBusy):
		c.JSON(http.StatusConflict, gin.H{"error": err.Error(), "code": "busy"})
	case errors.Is(err, repository.ErrCallNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error(), "code": "not_found"})
	case errors.Is(err, repository.ErrCallBadState):
		c.JSON(http.StatusConflict, gin.H{"error": err.Error(), "code": "bad_state"})
	default:
		log.Println("calls:", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "something went wrong"})
	}
}

// Create starts a call on a lead.
func (h *CallHandler) Create(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	var req models.CreateCallRequest
	if err := c.ShouldBindJSON(&req); err != nil || (req.LeadID == "" && req.PropertyID == "" && req.PeerID == "") {
		c.JSON(http.StatusBadRequest, gin.H{"error": "send lead_id, property_id (+ peer_id when you are the owner), or peer_id"})
		return
	}
	leadID, err := h.repo.ResolveLead(c.Request.Context(), userID, req.LeadID, req.PropertyID, req.PeerID)
	if err != nil {
		writeCallError(c, err)
		return
	}
	call, err := h.repo.Create(c.Request.Context(), leadID, userID)
	if err != nil {
		writeCallError(c, err)
		return
	}

	name := notify.UserName(userID)
	if name == "" {
		name = "Someone"
	}
	h.hub.sendTo(call.CalleeID, signalMsg{
		Type: "incoming", CallID: call.ID, From: userID,
		Data: mustJSON(map[string]string{"caller_name": name, "lead_id": call.LeadID}),
	})
	// Always push too: the callee's app may be closed. Route lets the app open
	// the incoming-call screen; the app dedupes on call_id.
	notify.SendRoute(call.CalleeID, "call", "Incoming call", name+" is calling you", "/call/"+call.ID)

	callCopy := *call
	time.AfterFunc(ringTimeout, func() { h.expireRinging(callCopy) })

	c.JSON(http.StatusCreated, gin.H{"call": call, "ice_servers": iceServersFor(userID)})
}

// Reject lets the callee decline from a push notification before the socket is up.
func (h *CallHandler) Reject(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	call, err := h.repo.Get(c.Request.Context(), c.Param("id"))
	if err != nil {
		writeCallError(c, err)
		return
	}
	if call.CalleeID != userID {
		writeCallError(c, repository.ErrCallForbidden)
		return
	}
	if call.Status != "ringing" {
		writeCallError(c, repository.ErrCallBadState)
		return
	}
	if !h.finish(c.Request.Context(), call, "rejected", "rejected") {
		writeCallError(c, repository.ErrCallBadState)
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "rejected"})
}

// IceServers returns STUN/TURN config (the callee fetches it after accepting).
func (h *CallHandler) IceServers(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ice_servers": iceServersFor(userID)})
}

func (h *CallHandler) History(c *gin.Context) {
	userID, err := middleware.GetUserID(c)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	// Optional ?peer_id= : only calls with that person (chat thread). Up to 100.
	peerID := strings.TrimSpace(c.Query("peer_id"))
	limit := 50
	if peerID != "" {
		limit = 100
	}
	calls, err := h.repo.ListForUser(c.Request.Context(), userID, peerID, limit)
	if err != nil {
		writeCallError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"calls": calls})
}

// ---------------------------------------------------------------- websocket

func (h *CallHandler) Socket(c *gin.Context) {
	token := strings.TrimSpace(strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer "))
	if token == "" {
		token = c.Query("token")
	}
	claims, err := middleware.ParseToken(token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
		return
	}
	userID, _ := claims["user_id"].(string)
	if userID == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token claims"})
		return
	}
	if h.repo.UserSuspended(c.Request.Context(), userID) {
		c.JSON(http.StatusForbidden, gin.H{"error": "account suspended"})
		return
	}

	ws, err := callUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return // Upgrade already wrote the HTTP error
	}
	conn := &callConn{userID: userID, ws: ws, send: make(chan []byte, 32)}
	h.hub.register(conn)
	go conn.writePump()
	h.readLoop(conn)
}

func (h *CallHandler) readLoop(conn *callConn) {
	defer func() {
		if h.hub.unregister(conn) {
			h.endOpenCalls(conn.userID)
		}
		_ = conn.ws.Close()
	}()
	conn.ws.SetReadLimit(64 * 1024)
	_ = conn.ws.SetReadDeadline(time.Now().Add(pongWait))
	conn.ws.SetPongHandler(func(string) error {
		return conn.ws.SetReadDeadline(time.Now().Add(pongWait))
	})
	for {
		_, data, err := conn.ws.ReadMessage()
		if err != nil {
			return
		}
		_ = conn.ws.SetReadDeadline(time.Now().Add(pongWait))
		var msg signalMsg
		if json.Unmarshal(data, &msg) != nil {
			continue
		}
		if msg.Type == "ping" {
			h.hub.sendTo(conn.userID, signalMsg{Type: "pong"})
			continue
		}
		h.handleSignal(conn, msg)
	}
}

func (h *CallHandler) handleSignal(conn *callConn, msg signalMsg) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	call, err := h.repo.Get(ctx, msg.CallID)
	if err != nil {
		h.hub.sendTo(conn.userID, errMsg(msg.CallID, "call not found"))
		return
	}
	isCaller := conn.userID == call.CallerID
	isCallee := conn.userID == call.CalleeID
	if !isCaller && !isCallee {
		h.hub.sendTo(conn.userID, errMsg(call.ID, "not your call"))
		return
	}
	peer := call.CallerID
	if isCaller {
		peer = call.CalleeID
	}

	switch msg.Type {
	case "accept":
		if !isCallee {
			h.hub.sendTo(conn.userID, errMsg(call.ID, "only the callee can accept"))
			return
		}
		ok, err := h.repo.MarkActive(ctx, call.ID)
		if err != nil || !ok {
			h.hub.sendTo(conn.userID, errMsg(call.ID, "call is no longer ringing"))
			return
		}
		h.hub.sendTo(peer, signalMsg{Type: "accepted", CallID: call.ID})

	case "reject":
		if !isCallee {
			h.hub.sendTo(conn.userID, errMsg(call.ID, "only the callee can reject"))
			return
		}
		h.finish(ctx, call, "rejected", "rejected")

	case "end":
		status, reason := "ended", "ended"
		if call.Status == "ringing" {
			if isCaller {
				status, reason = "missed", "cancelled"
			} else {
				status, reason = "rejected", "rejected"
			}
		}
		h.finish(ctx, call, status, reason)

	case "offer", "answer", "ice":
		if call.Status != "active" {
			h.hub.sendTo(conn.userID, errMsg(call.ID, "call is not active"))
			return
		}
		if (msg.Type == "offer" && !isCaller) || (msg.Type == "answer" && !isCallee) {
			h.hub.sendTo(conn.userID, errMsg(call.ID, "wrong side for "+msg.Type))
			return
		}
		h.hub.sendTo(peer, signalMsg{Type: msg.Type, CallID: call.ID, Data: msg.Data})

	default:
		h.hub.sendTo(conn.userID, errMsg(call.ID, "unknown message type"))
	}
}

// ---------------------------------------------------------------- state helpers

// finish moves a ringing/active call to a final status and tells both sides.
func (h *CallHandler) finish(ctx context.Context, call *models.Call, status, reason string) bool {
	ok, err := h.repo.Finish(ctx, call.ID, status)
	if err != nil || !ok {
		return false
	}
	h.announceEnded(call, status, reason)
	return true
}

func (h *CallHandler) announceEnded(call *models.Call, status, reason string) {
	ended := signalMsg{Type: "ended", CallID: call.ID, Reason: reason}
	h.hub.sendTo(call.CallerID, ended)
	h.hub.sendTo(call.CalleeID, ended)
	if status == "missed" {
		name := notify.UserName(call.CallerID)
		if name == "" {
			name = "Someone"
		}
		notify.Send(call.CalleeID, "call", "Missed call", name+" tried to call you")
	}
}

func (h *CallHandler) expireRinging(call models.Call) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ok, err := h.repo.MarkMissed(ctx, call.ID)
	if err != nil || !ok {
		return
	}
	h.announceEnded(&call, "missed", "no_answer")
}

func (h *CallHandler) endOpenCalls(userID string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ended, err := h.repo.EndOpenCallsFor(ctx, userID)
	if err != nil {
		log.Println("calls: end open calls:", err)
		return
	}
	for i := range ended {
		h.announceEnded(&ended[i], ended[i].Status, "peer_disconnected")
	}
}

// ---------------------------------------------------------------- ICE servers

type iceServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

func splitEnv(key, fallback string) []string {
	raw := os.Getenv(key)
	if strings.TrimSpace(raw) == "" {
		raw = fallback
	}
	var out []string
	for _, p := range strings.Split(raw, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// iceServersFor builds the STUN/TURN list for one user.
//
//	STUN_URLS     comma list, default stun:stun.l.google.com:19302
//	TURN_URLS     comma list, e.g. turn:turn.example.com:3478?transport=udp,turns:turn.example.com:5349
//	TURN_SECRET   coturn "use-auth-secret": short-lived credentials are generated per user
//	TURN_USER / TURN_PASS   static credentials (managed TURN services), used when TURN_SECRET is empty
func iceServersFor(userID string) []iceServer {
	out := []iceServer{{URLs: splitEnv("STUN_URLS", "stun:stun.l.google.com:19302")}}

	turn := splitEnv("TURN_URLS", "")
	if len(turn) == 0 {
		return out
	}
	s := iceServer{URLs: turn}
	if secret := strings.TrimSpace(os.Getenv("TURN_SECRET")); secret != "" {
		expires := time.Now().Add(time.Hour).Unix()
		s.Username = fmt.Sprintf("%d:%s", expires, userID)
		mac := hmac.New(sha1.New, []byte(secret))
		mac.Write([]byte(s.Username))
		s.Credential = base64.StdEncoding.EncodeToString(mac.Sum(nil))
	} else {
		s.Username = os.Getenv("TURN_USER")
		s.Credential = os.Getenv("TURN_PASS")
	}
	return append(out, s)
}