package handlers

import (
	"fmt"
	"strconv"
	"strings"

	"proptech-backend/internal/models"

	"github.com/gin-gonic/gin"
)

func queryFloat(c *gin.Context, key string) (*float64, error) {
	raw := strings.TrimSpace(c.Query(key))
	if raw == "" {
		return nil, nil
	}
	v, err := strconv.ParseFloat(raw, 64)
	if err != nil {
		return nil, fmt.Errorf("%s must be a number", key)
	}
	return &v, nil
}

func queryCSV(c *gin.Context, key string) []string {
	var out []string
	for _, part := range strings.Split(c.Query(key), ",") {
		if part = strings.TrimSpace(part); part != "" {
			out = append(out, part)
		}
	}
	return out
}

func queryInt(c *gin.Context, key string) (int, error) {
	raw := strings.TrimSpace(c.Query(key))
	if raw == "" {
		return 0, nil
	}
	v, err := strconv.Atoi(raw)
	if err != nil || v < 0 {
		return 0, fmt.Errorf("%s must be a non-negative integer", key)
	}
	return v, nil
}

// parsePropertyFilter reads the search query params of GET /api/properties:
//
//	q, location, city, locality, category, status, posted_by, sort
//	bhk=2 BHK,3 BHK        furnishing=Furnished,Semi Furnished     amenities=Lift,Parking
//	min_price, max_price, min_area, max_area, min_bathrooms, verified=true
//	lat, lng, radius_km                          (near me; sort=distance)
//	min_lat, max_lat, min_lng, max_lng           (map viewport)
//	page, limit                                  (limit<=100; omit for all)
func parsePropertyFilter(c *gin.Context) (models.PropertyFilter, error) {
	f := models.PropertyFilter{
		Query:         c.Query("q"),
		Location:      c.Query("location"),
		City:          c.Query("city"),
		Locality:      c.Query("locality"),
		Category:      c.Query("category"),
		ListingStatus: c.Query("status"),
		PostedBy:      c.Query("posted_by"),
		Sort:          c.Query("sort"),
		BHK:           queryCSV(c, "bhk"),
		Furnishing:    queryCSV(c, "furnishing"),
		Amenities:     queryCSV(c, "amenities"),
		VerifiedOnly:  c.Query("verified") == "true" || c.Query("verified") == "1",
	}

	floats := []struct {
		key string
		dst **float64
	}{
		{"min_price", &f.MinPrice}, {"max_price", &f.MaxPrice},
		{"min_area", &f.MinArea}, {"max_area", &f.MaxArea},
		{"lat", &f.Lat}, {"lng", &f.Lng}, {"radius_km", &f.RadiusKm},
		{"min_lat", &f.MinLat}, {"max_lat", &f.MaxLat},
		{"min_lng", &f.MinLng}, {"max_lng", &f.MaxLng},
	}
	for _, fl := range floats {
		v, err := queryFloat(c, fl.key)
		if err != nil {
			return f, err
		}
		*fl.dst = v
	}

	if (f.Lat == nil) != (f.Lng == nil) {
		return f, fmt.Errorf("lat and lng must be sent together")
	}
	if f.Lat != nil && (*f.Lat < -90 || *f.Lat > 90 || *f.Lng < -180 || *f.Lng > 180) {
		return f, fmt.Errorf("lat must be -90..90 and lng -180..180")
	}

	if raw := strings.TrimSpace(c.Query("min_bathrooms")); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 0 {
			return f, fmt.Errorf("min_bathrooms must be a non-negative integer")
		}
		f.MinBathrooms = &n
	}

	var err error
	if f.Page, err = queryInt(c, "page"); err != nil {
		return f, err
	}
	if f.Limit, err = queryInt(c, "limit"); err != nil {
		return f, err
	}
	// page without limit -> sensible default page size
	if f.Page > 0 && f.Limit == 0 {
		f.Limit = 20
	}
	return f, nil
}
