package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"proptech-backend/internal/models"
)

type FavoriteRepository struct {
	db *pgxpool.Pool
}

func NewFavoriteRepository(db *pgxpool.Pool) *FavoriteRepository {
	return &FavoriteRepository{db: db}
}

// Add marks a property as favorite for a user. Safe to call again (no duplicate error).
func (r *FavoriteRepository) Add(ctx context.Context, req models.AddFavoriteRequest) (*models.Favorite, error) {
	var f models.Favorite
	err := r.db.QueryRow(ctx, `
		INSERT INTO favorites (user_id, property_id)
		VALUES ($1, $2)
		ON CONFLICT (user_id, property_id) DO UPDATE SET user_id = EXCLUDED.user_id
		RETURNING id, user_id, property_id, created_at
	`, req.UserID, req.PropertyID).Scan(&f.ID, &f.UserID, &f.PropertyID, &f.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &f, nil
}

// Remove un-favorites a property for a user.
func (r *FavoriteRepository) Remove(ctx context.Context, userID string, propertyID string) error {
	_, err := r.db.Exec(ctx, `
		DELETE FROM favorites WHERE user_id = $1 AND property_id = $2
	`, userID, propertyID)
	return err
}

// GetByUserID returns the full Property objects a user has favorited
// (matches what the frontend Favorites screen needs to render property cards).
func (r *FavoriteRepository) GetByUserID(ctx context.Context, userID string) ([]models.Property, error) {
	rows, err := r.db.Query(ctx, `
		SELECT p.id, p.owner_id, p.title, p.image_url, p.price, p.price_unit, p.bhk, p.furnishing, p.location,
		       p.is_verified, p.rating, p.review_count, p.category, p.amenities, p.created_at
		FROM favorites f
		JOIN properties p ON p.id = f.property_id
		WHERE f.user_id = $1
		ORDER BY f.created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var properties []models.Property
	for rows.Next() {
		var p models.Property
		err := rows.Scan(&p.ID, &p.OwnerID, &p.Title, &p.ImageURL, &p.Price, &p.PriceUnit, &p.BHK, &p.Furnishing, &p.Location, &p.IsVerified, &p.Rating, &p.ReviewCount, &p.Category, &p.Amenities, &p.CreatedAt)
		if err != nil {
			return nil, err
		}
		properties = append(properties, p)
	}

	return properties, nil
}