package repository

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"
	"proptech-backend/internal/models"
)

type PropertyRepository struct {
	db *pgxpool.Pool
}

func NewPropertyRepository(db *pgxpool.Pool) *PropertyRepository {
	return &PropertyRepository{db: db}
}

func (r *PropertyRepository) GetAll(ctx context.Context) ([]models.Property, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, owner_id, title, image_url, price, price_unit, bhk, furnishing, location, is_verified, rating, review_count, category, amenities, listing_status, created_at
		FROM properties
		ORDER BY created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var properties []models.Property
	for rows.Next() {
		var p models.Property
		err := rows.Scan(&p.ID, &p.OwnerID, &p.Title, &p.ImageURL, &p.Price, &p.PriceUnit, &p.BHK, &p.Furnishing, &p.Location, &p.IsVerified, &p.Rating, &p.ReviewCount, &p.Category, &p.Amenities, &p.ListingStatus, &p.CreatedAt)
		if err != nil {
			return nil, err
		}
		properties = append(properties, p)
	}

	return properties, nil
}

func (r *PropertyRepository) GetByID(ctx context.Context, id string) (*models.Property, error) {
	var p models.Property
	err := r.db.QueryRow(ctx, `
		SELECT id, owner_id, title, image_url, price, price_unit, bhk, furnishing, location, is_verified, rating, review_count, category, amenities, listing_status, created_at
		FROM properties
		WHERE id = $1
	`, id).Scan(&p.ID, &p.OwnerID, &p.Title, &p.ImageURL, &p.Price, &p.PriceUnit, &p.BHK, &p.Furnishing, &p.Location, &p.IsVerified, &p.Rating, &p.ReviewCount, &p.Category, &p.Amenities, &p.ListingStatus, &p.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// GetByOwnerID returns all properties listed by a specific owner
// (used for the "My Properties" / Owner Dashboard screens).
func (r *PropertyRepository) GetByOwnerID(ctx context.Context, ownerID string) ([]models.Property, error) {
	rows, err := r.db.Query(ctx, `
		SELECT id, owner_id, title, image_url, price, price_unit, bhk, furnishing, location, is_verified, rating, review_count, category, amenities, listing_status, created_at
		FROM properties
		WHERE owner_id = $1
		ORDER BY created_at DESC
	`, ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var properties []models.Property
	for rows.Next() {
		var p models.Property
		err := rows.Scan(&p.ID, &p.OwnerID, &p.Title, &p.ImageURL, &p.Price, &p.PriceUnit, &p.BHK, &p.Furnishing, &p.Location, &p.IsVerified, &p.Rating, &p.ReviewCount, &p.Category, &p.Amenities, &p.ListingStatus, &p.CreatedAt)
		if err != nil {
			return nil, err
		}
		properties = append(properties, p)
	}

	return properties, nil
}

func (r *PropertyRepository) Create(ctx context.Context, req models.CreatePropertyRequest) (*models.Property, error) {
	var p models.Property
	err := r.db.QueryRow(ctx, `
		INSERT INTO properties (owner_id, title, image_url, price, price_unit, bhk, furnishing, location, category, amenities)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		RETURNING id, owner_id, title, image_url, price, price_unit, bhk, furnishing, location, is_verified, rating, review_count, category, amenities, listing_status, created_at
	`, req.OwnerID, req.Title, req.ImageURL, req.Price, req.PriceUnit, req.BHK, req.Furnishing, req.Location, req.Category, req.Amenities).
		Scan(&p.ID, &p.OwnerID, &p.Title, &p.ImageURL, &p.Price, &p.PriceUnit, &p.BHK, &p.Furnishing, &p.Location, &p.IsVerified, &p.Rating, &p.ReviewCount, &p.Category, &p.Amenities, &p.ListingStatus, &p.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *PropertyRepository) Update(ctx context.Context, id string, req models.UpdatePropertyRequest) (*models.Property, error) {
	var p models.Property
	err := r.db.QueryRow(ctx, `
		UPDATE properties
		SET title = $1, image_url = $2, price = $3, price_unit = $4, bhk = $5, furnishing = $6, location = $7, category = $8, amenities = $9
		WHERE id = $10
		RETURNING id, owner_id, title, image_url, price, price_unit, bhk, furnishing, location, is_verified, rating, review_count, category, amenities, listing_status, created_at
	`, req.Title, req.ImageURL, req.Price, req.PriceUnit, req.BHK, req.Furnishing, req.Location, req.Category, req.Amenities, id).
		Scan(&p.ID, &p.OwnerID, &p.Title, &p.ImageURL, &p.Price, &p.PriceUnit, &p.BHK, &p.Furnishing, &p.Location, &p.IsVerified, &p.Rating, &p.ReviewCount, &p.Category, &p.Amenities, &p.ListingStatus, &p.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// UpdateListingStatus marks a property Available, Rented, or Sold —
// used by My Properties (owner/broker) to update the stat pills shown
// on their dashboard.
func (r *PropertyRepository) UpdateListingStatus(ctx context.Context, id string, status string) (*models.Property, error) {
	var p models.Property
	err := r.db.QueryRow(ctx, `
		UPDATE properties
		SET listing_status = $1
		WHERE id = $2
		RETURNING id, owner_id, title, image_url, price, price_unit, bhk, furnishing, location, is_verified, rating, review_count, category, amenities, listing_status, created_at
	`, status, id).
		Scan(&p.ID, &p.OwnerID, &p.Title, &p.ImageURL, &p.Price, &p.PriceUnit, &p.BHK, &p.Furnishing, &p.Location, &p.IsVerified, &p.Rating, &p.ReviewCount, &p.Category, &p.Amenities, &p.ListingStatus, &p.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// GetDashboardStats aggregates one owner/broker's listings by status, plus
// their active leads (open conversations) and visits scheduled in the next
// 7 days — backs OwnerDashboardScreen / BrokerDashboardScreen's stat cards.
func (r *PropertyRepository) GetDashboardStats(ctx context.Context, ownerID string) (*models.DashboardStats, error) {
	var s models.DashboardStats

	err := r.db.QueryRow(ctx, `
		SELECT
			COUNT(*) AS total,
			COUNT(*) FILTER (WHERE listing_status = 'available') AS available,
			COUNT(*) FILTER (WHERE listing_status = 'rented') AS rented,
			COUNT(*) FILTER (WHERE listing_status = 'sold') AS sold
		FROM properties
		WHERE owner_id = $1
	`, ownerID).Scan(&s.TotalProperties, &s.Available, &s.Rented, &s.Sold)
	if err != nil {
		return nil, err
	}

	err = r.db.QueryRow(ctx, `
		SELECT COUNT(DISTINCT sender_id)
		FROM messages
		WHERE receiver_id = $1
	`, ownerID).Scan(&s.ActiveLeads)
	if err != nil {
		return nil, err
	}

	err = r.db.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM visits v
		JOIN properties p ON p.id = v.property_id
		WHERE p.owner_id = $1
		  AND v.scheduled_at BETWEEN NOW() AND NOW() + INTERVAL '7 days'
	`, ownerID).Scan(&s.VisitsThisWeek)
	if err != nil {
		return nil, err
	}

	return &s, nil
}

func (r *PropertyRepository) Delete(ctx context.Context, id string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM properties WHERE id = $1`, id)
	return err
}