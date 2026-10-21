package repository

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"errors"
	"fmt"
	"math/big"
	"time"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

type VisitRepository struct {
	db *pgxpool.Pool
}

func NewVisitRepository(db *pgxpool.Pool) *VisitRepository {
	return &VisitRepository{db: db}
}

const visitSelectQuery = `
	SELECT v.id, v.property_id, p.title, p.image_url, v.visitor_id, u.name, v.scheduled_at, v.status, v.created_at,
		COALESCE(v.feedback_interest, ''), COALESCE(v.feedback_note, ''), v.feedback_at,
		COALESCE(v.reschedule_count, 0), v.rescheduled_at, (v.otp_verified_at IS NOT NULL)
	FROM visits v
	JOIN properties p ON p.id = v.property_id
	JOIN users u ON u.id = v.visitor_id
`

func scanVisit(row interface {
	Scan(dest ...any) error
}) (*models.Visit, error) {
	var v models.Visit
	err := row.Scan(&v.ID, &v.PropertyID, &v.PropertyTitle, &v.PropertyImageURL, &v.VisitorID, &v.VisitorName, &v.ScheduledAt, &v.Status, &v.CreatedAt,
		&v.FeedbackInterest, &v.FeedbackNote, &v.FeedbackAt, &v.RescheduleCount, &v.RescheduledAt, &v.OTPVerified)
	if err != nil {
		return nil, err
	}
	return &v, nil
}

// GetByVisitorID returns all visits scheduled by a given tenant/buyer (visitor).
func (r *VisitRepository) GetByVisitorID(ctx context.Context, visitorID string) ([]models.Visit, error) {
	rows, err := r.db.Query(ctx, visitSelectQuery+` WHERE v.visitor_id = $1 ORDER BY v.scheduled_at DESC`, visitorID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var visits []models.Visit
	for rows.Next() {
		v, err := scanVisit(rows)
		if err != nil {
			return nil, err
		}
		visits = append(visits, *v)
	}
	return visits, nil
}

// GetByOwnerID returns all visits for properties owned by a given owner
// (used by the Owner Dashboard to see who's visiting their listings).
func (r *VisitRepository) GetByOwnerID(ctx context.Context, ownerID string) ([]models.Visit, error) {
	rows, err := r.db.Query(ctx, visitSelectQuery+` WHERE p.owner_id = $1 ORDER BY v.scheduled_at DESC`, ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var visits []models.Visit
	for rows.Next() {
		v, err := scanVisit(rows)
		if err != nil {
			return nil, err
		}
		visits = append(visits, *v)
	}
	return visits, nil
}

func (r *VisitRepository) GetByID(ctx context.Context, id string) (*models.Visit, error) {
	row := r.db.QueryRow(ctx, visitSelectQuery+` WHERE v.id = $1`, id)
	return scanVisit(row)
}

func (r *VisitRepository) Create(ctx context.Context, req models.CreateVisitRequest) (*models.Visit, error) {
	var id string
	err := r.db.QueryRow(ctx, `
		INSERT INTO visits (property_id, visitor_id, scheduled_at, status)
		VALUES ($1, $2, $3, 'pending')
		RETURNING id
	`, req.PropertyID, req.VisitorID, req.ScheduledAt).Scan(&id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

func (r *VisitRepository) UpdateStatus(ctx context.Context, id string, status string) (*models.Visit, error) {
	_, err := r.db.Exec(ctx, `UPDATE visits SET status = $1 WHERE id = $2`, status, id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

func (r *VisitRepository) Delete(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM visits WHERE id = $1`, id)
	return err
}

// SetFeedback stores (or overwrites) the visitor's feedback for a visit.
func (r *VisitRepository) SetFeedback(ctx context.Context, id, interest, note string) (*models.Visit, error) {
	_, err := r.db.Exec(ctx, `
		UPDATE visits SET feedback_interest = $1, feedback_note = $2, feedback_at = NOW()
		WHERE id = $3
	`, interest, note, id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

// Reschedule moves a visit to a new time, sets its new status and bumps the
// reschedule counter.
func (r *VisitRepository) Reschedule(ctx context.Context, id string, scheduledAt time.Time, status string) (*models.Visit, error) {
	_, err := r.db.Exec(ctx, `
		UPDATE visits
		SET scheduled_at = $1, status = $2, reschedule_count = COALESCE(reschedule_count, 0) + 1, rescheduled_at = NOW()
		WHERE id = $3
	`, scheduledAt, status, id)
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

// CanContact: true once a visit between the two users is confirmed/completed.
func (r *VisitRepository) CanContact(ctx context.Context, a, b string) (bool, error) {
	return VisitAccepted(ctx, r.db, a, b)
}

// ---- Visit OTP --------------------------------------------------------

var (
	ErrVisitNotConfirmed = errors.New("this visit is not confirmed yet")
	ErrVisitOTPInvalid   = errors.New("incorrect OTP")
	ErrVisitOTPExpired   = errors.New("this OTP has expired - the visit needs to be rescheduled")
	ErrVisitOTPNotReady  = errors.New("the visitor has not received an OTP yet - ask them to open Visit Requests in the app")
	ErrVisitOTPLocked    = errors.New("too many wrong attempts - a new OTP has been generated in the visitor's app")
)

const (
	visitOTPMaxAttempts = 5
	visitOTPValidFor    = 24 * time.Hour // counted from the scheduled visit time
)

func newVisitOTP() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

// IssueOTP creates a fresh 6-digit OTP for the visit (resets attempts).
func (r *VisitRepository) IssueOTP(ctx context.Context, id string, scheduledAt time.Time) (string, error) {
	code, err := newVisitOTP()
	if err != nil {
		return "", err
	}
	_, err = r.db.Exec(ctx, `
		UPDATE visits
		SET otp_code = $1, otp_expires_at = $2, otp_attempts = 0, otp_verified_at = NULL
		WHERE id = $3`, code, scheduledAt.Add(visitOTPValidFor), id)
	if err != nil {
		return "", err
	}
	return code, nil
}

// AttachOTPs fills OTPCode on the visitor's own confirmed, not-yet-verified
// visits. A confirmed visit that has no OTP yet (e.g. confirmed before this
// feature existed) gets one issued here. Only call this for the visitor's list.
func (r *VisitRepository) AttachOTPs(ctx context.Context, visits []models.Visit) error {
	index := map[string]int{}
	ids := []string{}
	for i, v := range visits {
		if v.Status == "confirmed" && !v.OTPVerified {
			index[v.ID] = i
			ids = append(ids, v.ID)
		}
	}
	if len(ids) == 0 {
		return nil
	}

	rows, err := r.db.Query(ctx, `
		SELECT id::text, COALESCE(otp_code, ''), otp_expires_at, scheduled_at
		FROM visits WHERE id::text = ANY($1)`, ids)
	if err != nil {
		return err
	}
	type pending struct {
		id          string
		scheduledAt time.Time
	}
	var needNew []pending
	for rows.Next() {
		var id, code string
		var expires *time.Time
		var scheduledAt time.Time
		if err := rows.Scan(&id, &code, &expires, &scheduledAt); err != nil {
			rows.Close()
			return err
		}
		switch {
		case code == "":
			needNew = append(needNew, pending{id, scheduledAt})
		case expires == nil || time.Now().Before(*expires):
			visits[index[id]].OTPCode = code
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	for _, n := range needNew {
		code, err := r.IssueOTP(ctx, n.id, n.scheduledAt)
		if err != nil {
			return err
		}
		visits[index[n.id]].OTPCode = code
	}
	return nil
}

// VerifyOTP checks the code the owner typed. On success the visit becomes
// "completed". After visitOTPMaxAttempts wrong tries the code is replaced
// with a new one (the buyer sees it in the app) and ErrVisitOTPLocked is returned.
func (r *VisitRepository) VerifyOTP(ctx context.Context, id, code string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	var status string
	var stored *string
	var expires *time.Time
	var attempts int
	var scheduledAt time.Time
	err = tx.QueryRow(ctx, `
		SELECT status, otp_code, otp_expires_at, COALESCE(otp_attempts, 0), scheduled_at
		FROM visits WHERE id = $1 FOR UPDATE`, id).Scan(&status, &stored, &expires, &attempts, &scheduledAt)
	if err != nil {
		return err
	}
	if status != "confirmed" {
		return ErrVisitNotConfirmed
	}
	if stored == nil || *stored == "" {
		return ErrVisitOTPNotReady
	}
	if expires != nil && time.Now().After(*expires) {
		return ErrVisitOTPExpired
	}

	if subtle.ConstantTimeCompare([]byte(*stored), []byte(code)) == 1 {
		if _, err := tx.Exec(ctx, `
			UPDATE visits
			SET status = 'completed', otp_verified_at = NOW(), otp_code = NULL, otp_attempts = 0
			WHERE id = $1`, id); err != nil {
			return err
		}
		return tx.Commit(ctx)
	}

	attempts++
	if attempts >= visitOTPMaxAttempts {
		fresh, err := newVisitOTP()
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE visits SET otp_code = $1, otp_attempts = 0 WHERE id = $2`, fresh, id); err != nil {
			return err
		}
		if err := tx.Commit(ctx); err != nil {
			return err
		}
		return ErrVisitOTPLocked
	}
	if _, err := tx.Exec(ctx, `UPDATE visits SET otp_attempts = $1 WHERE id = $2`, attempts, id); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	return ErrVisitOTPInvalid
}