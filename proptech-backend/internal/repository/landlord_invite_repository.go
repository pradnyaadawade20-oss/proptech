package repository

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"errors"
	"math/big"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"proptech-backend/internal/models"
)

var (
	ErrInviteNotBrokerListing = errors.New("only broker listings that you posted can be linked to an owner")
	ErrInviteAlreadyLinked    = errors.New("this property already has an owner linked")
	ErrInviteNotFound         = errors.New("invite not found or no longer valid")
	ErrInviteForbidden        = errors.New("this invite was not sent to you")
	ErrInviteSelf             = errors.New("you cannot accept your own invite")
)

const inviteValidDays = 14

// No 0/O/1/I so the code is easy to read out over a call.
const inviteAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

type LandlordInviteRepository struct {
	db *pgxpool.Pool
}

func NewLandlordInviteRepository(db *pgxpool.Pool) *LandlordInviteRepository {
	return &LandlordInviteRepository{db: db}
}

type inviteQuerier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

const inviteSelect = `
	SELECT i.id, i.property_id, p.title, i.broker_id, bu.name, i.code,
	       i.landlord_name, COALESCE(i.landlord_phone, ''), COALESCE(i.landlord_email, ''),
	       COALESCE(i.landlord_user_id::text, ''), COALESCE(lu.name, ''),
	       i.status, i.expires_at, i.created_at, i.responded_at
	FROM landlord_invites i
	JOIN properties p ON p.id = i.property_id
	JOIN users bu ON bu.id = i.broker_id
	LEFT JOIN users lu ON lu.id = i.landlord_user_id
`

// SQL condition: invite `i` was addressed to user `me` (by linked account, email or phone).
const inviteAddressedToMe = `
	i.broker_id <> me.id AND (
		i.landlord_user_id = me.id
		OR (COALESCE(i.landlord_email, '') <> '' AND LOWER(i.landlord_email) = LOWER(COALESCE(me.email, '')))
		OR (COALESCE(i.landlord_phone, '') <> ''
		    AND LENGTH(regexp_replace(i.landlord_phone, '\D', '', 'g')) >= 10
		    AND RIGHT(regexp_replace(i.landlord_phone, '\D', '', 'g'), 10) = RIGHT(regexp_replace(COALESCE(me.phone, ''), '\D', '', 'g'), 10))
	)
`

func scanInvite(row interface{ Scan(dest ...any) error }) (*models.LandlordInvite, error) {
	var v models.LandlordInvite
	err := row.Scan(
		&v.ID, &v.PropertyID, &v.PropertyTitle, &v.BrokerID, &v.BrokerName, &v.Code,
		&v.LandlordName, &v.LandlordPhone, &v.LandlordEmail,
		&v.LandlordUserID, &v.LandlordUserName,
		&v.Status, &v.ExpiresAt, &v.CreatedAt, &v.RespondedAt,
	)
	if err != nil {
		return nil, err
	}
	if v.Status == "pending" && v.ExpiresAt.Before(time.Now()) {
		v.Status = "expired"
	}
	return &v, nil
}

func newInviteCode() (string, error) {
	out := make([]byte, 8)
	max := big.NewInt(int64(len(inviteAlphabet)))
	for i := range out {
		n, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		out[i] = inviteAlphabet[n.Int64()]
	}
	return string(out), nil
}

// NormalizeInviteCode upper-cases and strips spaces/dashes ("abcd-2345" -> "ABCD2345").
func NormalizeInviteCode(code string) string {
	code = strings.ToUpper(strings.TrimSpace(code))
	code = strings.ReplaceAll(code, "-", "")
	return strings.ReplaceAll(code, " ", "")
}

// Create makes a new pending invite for a broker listing (cancelling any older pending one).
func (r *LandlordInviteRepository) Create(ctx context.Context, propertyID, brokerID, name, phone, email string) (*models.LandlordInvite, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var ownerID, postedBy string
	var landlordID *string
	err = tx.QueryRow(ctx,
		`SELECT COALESCE(owner_id::text, ''), COALESCE(posted_by, 'owner'), landlord_id::text FROM properties WHERE id = $1 FOR UPDATE`,
		propertyID,
	).Scan(&ownerID, &postedBy, &landlordID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrInviteNotFound
	}
	if err != nil {
		return nil, err
	}
	if ownerID != brokerID || postedBy != "broker" {
		return nil, ErrInviteNotBrokerListing
	}
	if landlordID != nil {
		return nil, ErrInviteAlreadyLinked
	}

	if _, err := tx.Exec(ctx,
		`UPDATE landlord_invites SET status = 'cancelled', responded_at = now()
		 WHERE property_id = $1 AND status = 'pending'`, propertyID); err != nil {
		return nil, err
	}

	// If the owner already has an account, link it so they get a notification.
	var matchedUser *string
	err = tx.QueryRow(ctx, `
		SELECT id::text FROM users
		WHERE id <> $3::uuid AND (
			($1 <> '' AND LOWER(email) = LOWER($1))
			OR ($2 <> '' AND RIGHT(regexp_replace(phone, '\D', '', 'g'), 10) = RIGHT(regexp_replace($2, '\D', '', 'g'), 10))
		)
		LIMIT 1`, email, phone, brokerID).Scan(&matchedUser)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	var code string
	for attempt := 0; attempt < 5; attempt++ {
		c, err := newInviteCode()
		if err != nil {
			return nil, err
		}
		var taken bool
		if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM landlord_invites WHERE code = $1)`, c).Scan(&taken); err != nil {
			return nil, err
		}
		if !taken {
			code = c
			break
		}
	}
	if code == "" {
		return nil, errors.New("could not generate an invite code, please try again")
	}

	var id string
	err = tx.QueryRow(ctx, `
		INSERT INTO landlord_invites
			(property_id, broker_id, code, landlord_name, landlord_phone, landlord_email, landlord_user_id, expires_at)
		VALUES ($1, $2, $3, $4, NULLIF($5, ''), NULLIF($6, ''), $7, now() + make_interval(days => $8))
		RETURNING id`,
		propertyID, brokerID, code, name, phone, email, matchedUser, inviteValidDays,
	).Scan(&id)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return scanInvite(r.db.QueryRow(ctx, inviteSelect+` WHERE i.id = $1`, id))
}

// LatestForProperty is the broker's view (code included). nil when never invited.
func (r *LandlordInviteRepository) LatestForProperty(ctx context.Context, propertyID, brokerID string) (*models.LandlordInvite, error) {
	inv, err := scanInvite(r.db.QueryRow(ctx,
		inviteSelect+` WHERE i.property_id = $1 AND i.broker_id = $2 ORDER BY i.created_at DESC LIMIT 1`,
		propertyID, brokerID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return inv, err
}

// Cancel withdraws the broker's pending invite. Returns false if there was none.
func (r *LandlordInviteRepository) Cancel(ctx context.Context, propertyID, brokerID string) (bool, error) {
	tag, err := r.db.Exec(ctx,
		`UPDATE landlord_invites SET status = 'cancelled', responded_at = now()
		 WHERE property_id = $1 AND broker_id = $2 AND status = 'pending'`, propertyID, brokerID)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// ListMine returns open invites addressed to this user (the code is never included).
func (r *LandlordInviteRepository) ListMine(ctx context.Context, userID string) ([]models.LandlordInvite, error) {
	rows, err := r.db.Query(ctx, inviteSelect+`
		JOIN users me ON me.id = $1::uuid
		WHERE i.status = 'pending' AND i.expires_at > now() AND `+inviteAddressedToMe+`
		ORDER BY i.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	out := []models.LandlordInvite{}
	for rows.Next() {
		inv, err := scanInvite(rows)
		if err != nil {
			return nil, err
		}
		inv.Code = ""
		out = append(out, *inv)
	}
	return out, rows.Err()
}

// GetByCode looks up an open invite by its code (the code is never echoed back).
func (r *LandlordInviteRepository) GetByCode(ctx context.Context, code string) (*models.LandlordInvite, error) {
	inv, err := scanInvite(r.db.QueryRow(ctx,
		inviteSelect+` WHERE i.code = $1 AND i.status = 'pending' AND i.expires_at > now()`, NormalizeInviteCode(code)))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrInviteNotFound
	}
	if err != nil {
		return nil, err
	}
	inv.Code = ""
	return inv, nil
}

func (r *LandlordInviteRepository) userIsAddressed(ctx context.Context, q inviteQuerier, inviteID, userID string) (bool, error) {
	var ok bool
	err := q.QueryRow(ctx, `
		SELECT EXISTS (
			SELECT 1 FROM landlord_invites i
			JOIN users me ON me.id = $2::uuid
			WHERE i.id = $1::uuid AND `+inviteAddressedToMe+`
		)`, inviteID, userID).Scan(&ok)
	return ok, err
}

// lockOpenInvite finds the invite (by id, or by code when id is empty) and locks it.
func (r *LandlordInviteRepository) lockOpenInvite(ctx context.Context, tx pgx.Tx, userID, inviteID, code string) (id, propertyID string, err error) {
	var brokerID, status, storedCode string
	var expires time.Time
	code = NormalizeInviteCode(code)

	switch {
	case inviteID != "":
		err = tx.QueryRow(ctx,
			`SELECT id::text, property_id::text, broker_id::text, status, code, expires_at
			 FROM landlord_invites WHERE id = $1::uuid FOR UPDATE`, inviteID,
		).Scan(&id, &propertyID, &brokerID, &status, &storedCode, &expires)
	case code != "":
		err = tx.QueryRow(ctx,
			`SELECT id::text, property_id::text, broker_id::text, status, code, expires_at
			 FROM landlord_invites WHERE code = $1 FOR UPDATE`, code,
		).Scan(&id, &propertyID, &brokerID, &status, &storedCode, &expires)
	default:
		return "", "", ErrInviteNotFound
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return "", "", ErrInviteNotFound
	}
	if err != nil {
		return "", "", err
	}
	if status != "pending" || expires.Before(time.Now()) {
		return "", "", ErrInviteNotFound
	}
	if brokerID == userID {
		return "", "", ErrInviteSelf
	}

	// Allowed if the user holds the secret code, or the invite was sent to their email/phone.
	if code != "" && subtle.ConstantTimeCompare([]byte(code), []byte(storedCode)) == 1 {
		return id, propertyID, nil
	}
	ok, err := r.userIsAddressed(ctx, tx, id, userID)
	if err != nil {
		return "", "", err
	}
	if !ok {
		return "", "", ErrInviteForbidden
	}
	return id, propertyID, nil
}

// Accept links the property to this user as its real owner (landlord).
func (r *LandlordInviteRepository) Accept(ctx context.Context, userID, inviteID, code string) (*models.LandlordInvite, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	id, propertyID, err := r.lockOpenInvite(ctx, tx, userID, inviteID, code)
	if err != nil {
		return nil, err
	}

	tag, err := tx.Exec(ctx,
		`UPDATE properties SET landlord_id = $1
		 WHERE id = $2 AND landlord_id IS NULL AND COALESCE(posted_by, 'owner') = 'broker'`, userID, propertyID)
	if err != nil {
		return nil, err
	}
	if tag.RowsAffected() == 0 {
		return nil, ErrInviteAlreadyLinked
	}
	if _, err := tx.Exec(ctx,
		`UPDATE landlord_invites SET status = 'accepted', landlord_user_id = $1, responded_at = now() WHERE id = $2`,
		userID, id); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	inv, err := scanInvite(r.db.QueryRow(ctx, inviteSelect+` WHERE i.id = $1`, id))
	if err != nil {
		return nil, err
	}
	inv.Code = ""
	return inv, nil
}

// Decline marks the invite declined; the property stays unlinked.
func (r *LandlordInviteRepository) Decline(ctx context.Context, userID, inviteID, code string) (*models.LandlordInvite, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	id, _, err := r.lockOpenInvite(ctx, tx, userID, inviteID, code)
	if err != nil {
		return nil, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE landlord_invites SET status = 'declined', landlord_user_id = $1, responded_at = now() WHERE id = $2`,
		userID, id); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	inv, err := scanInvite(r.db.QueryRow(ctx, inviteSelect+` WHERE i.id = $1`, id))
	if err != nil {
		return nil, err
	}
	inv.Code = ""
	return inv, nil
}

// AgreementEligibility tells the app whether tenants can request an agreement on this listing.
// Owner-posted listings: always. Broker listings: only once the real owner is linked.
func (r *LandlordInviteRepository) AgreementEligibility(ctx context.Context, propertyID string) (bool, string, error) {
	var postedBy string
	var landlordID *string
	err := r.db.QueryRow(ctx,
		`SELECT COALESCE(posted_by, 'owner'), landlord_id::text FROM properties WHERE id = $1`, propertyID,
	).Scan(&postedBy, &landlordID)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, "not_found", nil
	}
	if err != nil {
		return false, "", err
	}
	if postedBy != "broker" || landlordID != nil {
		return true, "", nil
	}
	return false, "owner_not_linked", nil
}