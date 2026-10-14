package repository

import (
	"context"
	"errors"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrCallNotFound  = errors.New("call not found")
	ErrCallForbidden = errors.New("you can only call the other person on your own lead")
	ErrCallBusy      = errors.New("one of you is already on a call")
	ErrCallBadState  = errors.New("call is not in a valid state for this action")
)

type CallRepository struct {
	db *pgxpool.Pool
}

func NewCallRepository(db *pgxpool.Pool) *CallRepository {
	return &CallRepository{db: db}
}

const callColumns = "id::text, lead_id::text, caller_id::text, callee_id::text, status, created_at, answered_at, ended_at"

func scanCall(row pgx.Row) (*models.Call, error) {
	var c models.Call
	if err := row.Scan(&c.ID, &c.LeadID, &c.CallerID, &c.CalleeID, &c.Status, &c.CreatedAt, &c.AnsweredAt, &c.EndedAt); err != nil {
		return nil, err
	}
	c.FillDuration()
	return &c, nil
}

// ResolveLead turns a call request into a lead id (see models.CreateCallRequest).
// A buyer calling from a listing gets a lead created on the fly (source "call");
// an owner can only call a buyer who already has a lead on that listing.
func (r *CallRepository) ResolveLead(ctx context.Context, callerID, leadID, propertyID, peerID string) (string, error) {
	if leadID != "" {
		return leadID, nil
	}
	if propertyID == "" {
		return "", ErrCallForbidden
	}

	var ownerID *string
	err := r.db.QueryRow(ctx, `SELECT owner_id::text FROM properties WHERE id = $1::uuid`, propertyID).Scan(&ownerID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return "", ErrCallNotFound
		}
		return "", err
	}
	if ownerID == nil {
		return "", ErrCallForbidden
	}

	var id string
	if *ownerID == callerID { // owner calling a buyer
		if peerID == "" {
			return "", ErrCallForbidden
		}
		err = r.db.QueryRow(ctx,
			`SELECT id::text FROM leads WHERE property_id = $1::uuid AND buyer_id = $2::uuid`, propertyID, peerID).Scan(&id)
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return "", ErrCallForbidden
			}
			return "", err
		}
		return id, nil
	}

	// buyer calling the owner
	err = r.db.QueryRow(ctx, `
		INSERT INTO leads (property_id, owner_id, buyer_id, name, phone, source)
		SELECT $1::uuid, $2::uuid, u.id, COALESCE(u.name, ''), COALESCE(u.phone, ''), 'call'
		FROM users u WHERE u.id = $3::uuid
		ON CONFLICT (property_id, buyer_id) DO UPDATE SET updated_at = now()
		RETURNING id::text`, propertyID, *ownerID, callerID).Scan(&id)
	if err != nil {
		return "", err
	}
	return id, nil
}

// Create starts a ringing call. The caller must be the buyer or the owner of
// the lead; the other person becomes the callee.
func (r *CallRepository) Create(ctx context.Context, leadID, callerID string) (*models.Call, error) {
	var buyerID, ownerID string
	err := r.db.QueryRow(ctx,
		`SELECT buyer_id::text, owner_id::text FROM leads WHERE id = $1::uuid`, leadID).Scan(&buyerID, &ownerID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrCallForbidden
		}
		return nil, err
	}

	var calleeID string
	switch callerID {
	case buyerID:
		calleeID = ownerID
	case ownerID:
		calleeID = buyerID
	default:
		return nil, ErrCallForbidden
	}
	if calleeID == callerID {
		return nil, ErrCallForbidden
	}

	var busy bool
	err = r.db.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM calls
			WHERE (caller_id = $1::uuid OR callee_id = $1::uuid OR caller_id = $2::uuid OR callee_id = $2::uuid)
			  AND ((status = 'ringing' AND created_at  > NOW() - INTERVAL '60 seconds')
			    OR (status = 'active'  AND answered_at > NOW() - INTERVAL '4 hours'))
		)`, callerID, calleeID).Scan(&busy)
	if err != nil {
		return nil, err
	}
	if busy {
		return nil, ErrCallBusy
	}

	return scanCall(r.db.QueryRow(ctx, `
		INSERT INTO calls (lead_id, caller_id, callee_id)
		VALUES ($1::uuid, $2::uuid, $3::uuid)
		RETURNING `+callColumns, leadID, callerID, calleeID))
}

func (r *CallRepository) Get(ctx context.Context, id string) (*models.Call, error) {
	c, err := scanCall(r.db.QueryRow(ctx, `SELECT `+callColumns+` FROM calls WHERE id = $1::uuid`, id))
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrCallNotFound
		}
		return nil, err
	}
	return c, nil
}

// MarkActive moves ringing -> active. false = it was not ringing any more.
func (r *CallRepository) MarkActive(ctx context.Context, id string) (bool, error) {
	tag, err := r.db.Exec(ctx,
		`UPDATE calls SET status = 'active', answered_at = NOW() WHERE id = $1::uuid AND status = 'ringing'`, id)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// MarkMissed moves ringing -> missed (ring timeout). false = already answered/ended.
func (r *CallRepository) MarkMissed(ctx context.Context, id string) (bool, error) {
	tag, err := r.db.Exec(ctx,
		`UPDATE calls SET status = 'missed', ended_at = NOW() WHERE id = $1::uuid AND status = 'ringing'`, id)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// Finish moves a ringing/active call to a final status (ended | rejected | missed).
func (r *CallRepository) Finish(ctx context.Context, id, status string) (bool, error) {
	tag, err := r.db.Exec(ctx,
		`UPDATE calls SET status = $2, ended_at = NOW() WHERE id = $1::uuid AND status IN ('ringing', 'active')`, id, status)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// EndOpenCallsFor is used when a user's signaling socket drops: their active
// calls end, and a call they were still ringing as the caller becomes missed.
// (A callee whose socket closes while ringing is NOT ended - the app may just
// have gone to the background.) Returns the calls it ended.
func (r *CallRepository) EndOpenCallsFor(ctx context.Context, userID string) ([]models.Call, error) {
	rows, err := r.db.Query(ctx, `
		UPDATE calls
		SET status = CASE WHEN status = 'ringing' THEN 'missed' ELSE 'ended' END, ended_at = NOW()
		WHERE (status = 'active'  AND (caller_id = $1::uuid OR callee_id = $1::uuid))
		   OR (status = 'ringing' AND caller_id = $1::uuid)
		RETURNING `+callColumns, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []models.Call
	for rows.Next() {
		c, err := scanCall(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, *c)
	}
	return out, rows.Err()
}

// ExpireStale runs at startup: anything still ringing/active belongs to a
// previous server process and can never complete.
func (r *CallRepository) ExpireStale(ctx context.Context) error {
	_, err := r.db.Exec(ctx, `
		UPDATE calls
		SET status = CASE WHEN status = 'ringing' THEN 'missed' ELSE 'ended' END, ended_at = NOW()
		WHERE status IN ('ringing', 'active')`)
	return err
}

func (r *CallRepository) UserSuspended(ctx context.Context, userID string) bool {
	var s bool
	if err := r.db.QueryRow(ctx, `SELECT suspended_at IS NOT NULL FROM users WHERE id = $1::uuid`, userID).Scan(&s); err != nil {
		return false
	}
	return s
}

// ListForUser is the call history (newest first) with the other person's name.
func (r *CallRepository) ListForUser(ctx context.Context, userID string, limit int) ([]models.Call, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	rows, err := r.db.Query(ctx, `
		SELECT c.id::text, c.lead_id::text, c.caller_id::text, c.callee_id::text, c.status,
		       c.created_at, c.answered_at, c.ended_at,
		       CASE WHEN c.caller_id = $1::uuid THEN 'outgoing' ELSE 'incoming' END,
		       COALESCE(u.name, '')
		FROM calls c
		JOIN users u ON u.id = CASE WHEN c.caller_id = $1::uuid THEN c.callee_id ELSE c.caller_id END
		WHERE c.caller_id = $1::uuid OR c.callee_id = $1::uuid
		ORDER BY c.created_at DESC
		LIMIT $2`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []models.Call{}
	for rows.Next() {
		var c models.Call
		if err := rows.Scan(&c.ID, &c.LeadID, &c.CallerID, &c.CalleeID, &c.Status,
			&c.CreatedAt, &c.AnsweredAt, &c.EndedAt, &c.Direction, &c.PeerName); err != nil {
			return nil, err
		}
		c.FillDuration()
		out = append(out, c)
	}
	return out, rows.Err()
}