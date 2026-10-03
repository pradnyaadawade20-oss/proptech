package repository

import (
	"context"
	"errors"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	// ErrAlreadyReviewed: this user already left a review on this property.
	ErrAlreadyReviewed = errors.New("you have already reviewed this property")
	// ErrReviewNotEligible: no completed visit on this property for this user.
	ErrReviewNotEligible = errors.New("you can review a property only after a completed visit")
)

type ReviewRepository struct {
	db *pgxpool.Pool
}

func NewReviewRepository(db *pgxpool.Pool) *ReviewRepository {
	return &ReviewRepository{db: db}
}

const reviewSelectQuery = `
	SELECT r.id, r.property_id, r.user_id, u.name, COALESCE(u.avatar_url, ''), r.rating, r.comment, r.created_at
	FROM reviews r
	JOIN users u ON u.id = r.user_id
`

func scanReview(row interface {
	Scan(dest ...any) error
}) (*models.Review, error) {
	var rv models.Review
	err := row.Scan(&rv.ID, &rv.PropertyID, &rv.UserID, &rv.UserName, &rv.UserAvatarURL, &rv.Rating, &rv.Comment, &rv.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &rv, nil
}

// GetByPropertyID returns all reviews for a property, newest first.
func (r *ReviewRepository) GetByPropertyID(ctx context.Context, propertyID string) ([]models.Review, error) {
	rows, err := r.db.Query(ctx, reviewSelectQuery+` WHERE r.property_id = $1 ORDER BY r.created_at DESC`, propertyID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	reviews := []models.Review{}
	for rows.Next() {
		rv, err := scanReview(rows)
		if err != nil {
			return nil, err
		}
		reviews = append(reviews, *rv)
	}
	return reviews, nil
}

// HasReviewed reports whether userID already left a review on propertyID —
// used by the handler to show/hide the "Write a review" button.
func (r *ReviewRepository) HasReviewed(ctx context.Context, propertyID, userID string) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM reviews WHERE property_id = $1 AND user_id = $2)`,
		propertyID, userID,
	).Scan(&exists)
	return exists, err
}

// HasCompletedVisit reports whether userID has a completed visit on
// propertyID — this is what unlocks the ability to review it, so a rating
// reflects someone who actually visited, not a drive-by 1-star.
func (r *ReviewRepository) HasCompletedVisit(ctx context.Context, propertyID, userID string) (bool, error) {
	var exists bool
	err := r.db.QueryRow(ctx,
		`SELECT EXISTS(
			SELECT 1 FROM visits
			WHERE property_id = $1 AND visitor_id = $2 AND status = 'completed'
		)`,
		propertyID, userID,
	).Scan(&exists)
	return exists, err
}

// Create inserts a review and recomputes the property's rating/review_count
// in the same transaction, so the two never drift apart.
func (r *ReviewRepository) Create(ctx context.Context, propertyID, userID string, req models.CreateReviewRequest) (*models.Review, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var id string
	err = tx.QueryRow(ctx, `
		INSERT INTO reviews (property_id, user_id, rating, comment)
		VALUES ($1, $2, $3, $4)
		RETURNING id
	`, propertyID, userID, req.Rating, req.Comment).Scan(&id)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" { // unique_violation
			return nil, ErrAlreadyReviewed
		}
		return nil, err
	}

	if _, err := tx.Exec(ctx, `
		UPDATE properties p
		SET rating = sub.avg_rating, review_count = sub.cnt
		FROM (
			SELECT ROUND(AVG(rating)::numeric, 1) AS avg_rating, COUNT(*) AS cnt
			FROM reviews WHERE property_id = $1
		) sub
		WHERE p.id = $1
	`, propertyID); err != nil {
		return nil, err
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}

	row := r.db.QueryRow(ctx, reviewSelectQuery+` WHERE r.id = $1`, id)
	return scanReview(row)
}
