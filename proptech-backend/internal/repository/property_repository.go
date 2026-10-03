package repository

import (
	"context"

	"proptech-backend/internal/models"

	"github.com/jackc/pgx/v5/pgxpool"
)

type PropertyRepository struct {
	db *pgxpool.Pool
}

// propertyColumns is the single source of truth for the property SELECT /
// RETURNING list; its order must match propertyDests below.
const propertyColumns = "id, owner_id, title, image_url, price, price_unit, bhk, furnishing, location, is_verified, rating, review_count, category, amenities, listing_status, created_at, area_sqft, bathrooms, balconies, floor_number, total_floors, city, locality, society, pincode, security_deposit, maintenance_charges, preferred_tenants, available_from, description, property_age_years, facing, ownership_type, is_price_negotiable, contact_preference, posted_by, latitude, longitude"

func NewPropertyRepository(db *pgxpool.Pool) *PropertyRepository {
	return &PropertyRepository{db: db}
}

func (r *PropertyRepository) GetAll(ctx context.Context) ([]models.Property, error) {
	properties, _, err := r.Search(ctx, models.PropertyFilter{})
	return properties, err
}

func (r *PropertyRepository) GetByID(ctx context.Context, id string) (*models.Property, error) {
	var p models.Property
	err := r.db.QueryRow(ctx, `
		SELECT `+propertyColumns+`
		FROM properties
		WHERE id = $1
	`, id).Scan(propertyDests(&p)...)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

// GetByOwnerID returns all properties listed by a specific owner
// (used for the "My Properties" / Owner Dashboard screens).
// SaveImage stores the actual uploaded photo bytes for a property and
// points image_url at the endpoint that serves them back
// (GET /api/properties/:id/image), so every screen that already renders
// image_url (home, buyer listings, property detail) shows the real photo.
func (r *PropertyRepository) SaveImage(ctx context.Context, id string, data []byte, contentType string, imageURL string) error {
	_, err := r.db.Exec(ctx, `
		UPDATE properties
		SET image_data = $1, image_content_type = $2, image_url = $3
		WHERE id = $4
	`, data, contentType, imageURL, id)
	return err
}

// GetImage returns the raw bytes + content type for a property's uploaded
// photo (nil, "", nil if none was ever uploaded — i.e. image_url is just
// a plain external URL, not one of ours).
func (r *PropertyRepository) GetImage(ctx context.Context, id string) ([]byte, string, error) {
	var data []byte
	var contentType *string
	err := r.db.QueryRow(ctx, `
		SELECT image_data, image_content_type FROM properties WHERE id = $1
	`, id).Scan(&data, &contentType)
	if err != nil {
		return nil, "", err
	}
	ct := ""
	if contentType != nil {
		ct = *contentType
	}
	return data, ct, nil
}

// SaveVerification stores the in-app camera photo + GPS coords captured
// for "Verify Now", and flips the property to verified. Called only after
// the handler has confirmed the photo's location is close enough to the
// listing's own address — this function trusts its caller.
func (r *PropertyRepository) SaveVerification(ctx context.Context, propertyID string, data []byte, contentType string, lat, lng float64) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, `
		INSERT INTO property_verifications (property_id, photo_data, content_type, latitude, longitude, captured_at)
		VALUES ($1, $2, $3, $4, $5, NOW())
		ON CONFLICT (property_id) DO UPDATE
		SET photo_data = EXCLUDED.photo_data, content_type = EXCLUDED.content_type,
		    latitude = EXCLUDED.latitude, longitude = EXCLUDED.longitude, captured_at = NOW()
	`, propertyID, data, contentType, lat, lng)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `
		UPDATE properties
		SET is_verified = TRUE,
		    latitude  = CASE WHEN latitude = 0 AND longitude = 0 THEN $2::float8 ELSE latitude END,
		    longitude = CASE WHEN latitude = 0 AND longitude = 0 THEN $3::float8 ELSE longitude END
		WHERE id = $1`, propertyID, lat, lng)
	if err != nil {
		return err
	}

	return tx.Commit(ctx)
}

// GetVerificationPhoto returns the raw bytes + content type of the photo
// captured for "Verify Now" (nil, "", nil if the property was never verified).
func (r *PropertyRepository) GetVerificationPhoto(ctx context.Context, propertyID string) ([]byte, string, error) {
	var data []byte
	var contentType string
	err := r.db.QueryRow(ctx, `
		SELECT photo_data, content_type FROM property_verifications WHERE property_id = $1
	`, propertyID).Scan(&data, &contentType)
	if err != nil {
		return nil, "", err
	}
	return data, contentType, nil
}

func (r *PropertyRepository) GetByOwnerID(ctx context.Context, ownerID string) ([]models.Property, error) {
	rows, err := r.db.Query(ctx, `
		SELECT `+propertyColumns+`
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
		err := rows.Scan(propertyDests(&p)...)
		if err != nil {
			return nil, err
		}
		properties = append(properties, p)
	}

	return properties, nil
}

func (r *PropertyRepository) Create(ctx context.Context, req models.CreatePropertyRequest) (*models.Property, error) {
	availableFrom, err := req.ParsedAvailableFrom()
	if err != nil {
		return nil, err
	}

	var p models.Property
	err = r.db.QueryRow(ctx, `
		INSERT INTO properties (
			owner_id, title, image_url, price, price_unit, bhk, furnishing, location, category, amenities,
			area_sqft, bathrooms, balconies, floor_number, total_floors, city, locality, society, pincode,
			security_deposit, maintenance_charges, preferred_tenants, available_from, description,
			property_age_years, facing, ownership_type, is_price_negotiable, contact_preference, posted_by,
			latitude, longitude
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
			$11, $12, $13, $14, $15, $16, $17, $18, $19,
			$20, $21, $22, $23, $24,
			$25, $26, $27, $28, $29, $30,
			$31, $32)
		RETURNING `+propertyColumns+`
	`, req.OwnerID, req.Title, req.ImageURL, req.Price, req.PriceUnit, req.BHK, req.Furnishing, req.Location, req.Category, req.Amenities,
		req.Area, req.Bathrooms, req.Balconies, req.FloorNumber, req.TotalFloors, req.City, req.Locality, req.Society, req.Pincode,
		req.SecurityDeposit, req.MaintenanceCharges, req.TenantsOrEmpty(), availableFrom, req.Description,
		req.AgeOrUnknown(), req.Facing, req.OwnershipType, req.IsPriceNegotiable, req.ContactPreferenceOrDefault(), req.PostedByOrDefault(),
		req.Latitude, req.Longitude).
		Scan(propertyDests(&p)...)
	if err != nil {
		return nil, err
	}
	return &p, nil
}

func (r *PropertyRepository) Update(ctx context.Context, id string, req models.UpdatePropertyRequest) (*models.Property, error) {
	availableFrom, err := req.ParsedAvailableFrom()
	if err != nil {
		return nil, err
	}

	var p models.Property
	err = r.db.QueryRow(ctx, `
		UPDATE properties
		SET title = $1, image_url = $2, price = $3, price_unit = $4, bhk = $5, furnishing = $6, location = $7, category = $8, amenities = $9,
			area_sqft = $10, bathrooms = $11, balconies = $12, floor_number = $13, total_floors = $14,
			city = $15, locality = $16, society = $17, pincode = $18,
			security_deposit = $19, maintenance_charges = $20, preferred_tenants = $21, available_from = $22, description = $23,
			property_age_years = $24, facing = $25, ownership_type = $26, is_price_negotiable = $27, contact_preference = $28,
			latitude  = CASE WHEN $29::float8 <> 0 OR $30::float8 <> 0 THEN $29::float8 ELSE latitude END,
			longitude = CASE WHEN $29::float8 <> 0 OR $30::float8 <> 0 THEN $30::float8 ELSE longitude END
		WHERE id = $31
		RETURNING `+propertyColumns+`
	`, req.Title, req.ImageURL, req.Price, req.PriceUnit, req.BHK, req.Furnishing, req.Location, req.Category, req.Amenities,
		req.Area, req.Bathrooms, req.Balconies, req.FloorNumber, req.TotalFloors,
		req.City, req.Locality, req.Society, req.Pincode,
		req.SecurityDeposit, req.MaintenanceCharges, req.TenantsOrEmpty(), availableFrom, req.Description,
		req.AgeOrUnknown(), req.Facing, req.OwnershipType, req.IsPriceNegotiable, req.ContactPreferenceOrDefault(), req.Latitude, req.Longitude, id).
		Scan(propertyDests(&p)...)
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
		RETURNING `+propertyColumns+`
	`, status, id).
		Scan(propertyDests(&p)...)
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
		SELECT COUNT(*)
		FROM leads
		WHERE owner_id = $1 AND status IN ('new', 'contacted')
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

// propertyDests lists the Scan targets for a row selected with the full
// property column list (same order everywhere: base columns, then details).
func propertyDests(p *models.Property) []any {
	return []any{
		&p.ID, &p.OwnerID, &p.Title, &p.ImageURL, &p.Price, &p.PriceUnit, &p.BHK, &p.Furnishing, &p.Location,
		&p.IsVerified, &p.Rating, &p.ReviewCount, &p.Category, &p.Amenities, &p.ListingStatus, &p.CreatedAt,
		&p.Area, &p.Bathrooms, &p.Balconies, &p.FloorNumber, &p.TotalFloors, &p.City, &p.Locality, &p.Society, &p.Pincode,
		&p.SecurityDeposit, &p.MaintenanceCharges, &p.PreferredTenants, &p.AvailableFrom, &p.Description,
		&p.PropertyAgeYears, &p.Facing, &p.OwnershipType, &p.IsPriceNegotiable, &p.ContactPreference, &p.PostedBy,
		&p.Latitude, &p.Longitude,
	}
}
