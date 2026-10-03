package repository

import (
	"regexp"
	"strings"
	"testing"

	"proptech-backend/internal/models"
)

func f64(v float64) *float64 { return &v }

func maxPlaceholder(sql string) int {
	re := regexp.MustCompile(`\$(\d+)`)
	m := 0
	for _, g := range re.FindAllStringSubmatch(sql, -1) {
		n := 0
		for _, c := range g[1] {
			n = n*10 + int(c-'0')
		}
		if n > m {
			m = n
		}
	}
	return m
}

func TestEmpty(t *testing.T) {
	w, a, o := BuildPropertySearch(models.PropertyFilter{})
	if w != "" || len(a) != 0 || o != "ORDER BY created_at DESC, id" {
		t.Fatalf("got %q %v %q", w, a, o)
	}
}

func TestFull(t *testing.T) {
	bath := 2
	f := models.PropertyFilter{
		Query: "andheri", City: "Mumbai", BHK: []string{"2 BHK", "3 BHK"}, Furnishing: []string{"Furnished"},
		Category: "Residential", PostedBy: "owner", MinPrice: f64(10000), MaxPrice: f64(50000),
		MinArea: f64(500), MinBathrooms: &bath, VerifiedOnly: true, Amenities: []string{"Lift"},
		Lat: f64(19.1), Lng: f64(72.8), RadiusKm: f64(5), Sort: "distance",
		MinLat: f64(1), MaxLat: f64(2), MinLng: f64(3), MaxLng: f64(4),
	}
	w, a, o := BuildPropertySearch(f)
	t.Log(w)
	t.Log(o)
	if maxPlaceholder(w+" "+o) != len(a) {
		t.Fatalf("placeholders %d != args %d", maxPlaceholder(w+" "+o), len(a))
	}
	if !strings.Contains(o, "acos") {
		t.Fatal("distance order missing")
	}
	if strings.Contains(w, "andheri") || strings.Contains(w, "Mumbai") {
		t.Fatal("user value leaked into SQL")
	}
}

func TestSortNoGeoFallsBack(t *testing.T) {
	_, _, o := BuildPropertySearch(models.PropertyFilter{Sort: "distance"})
	if o != "ORDER BY created_at DESC, id" {
		t.Fatal(o)
	}
	for s, want := range map[string]string{"price_low": "price ASC", "price_high": "price DESC", "rating": "rating DESC"} {
		_, _, o := BuildPropertySearch(models.PropertyFilter{Sort: s})
		if !strings.Contains(o, want) {
			t.Fatal(s, o)
		}
	}
	// injection attempt in sort is ignored
	_, _, o = BuildPropertySearch(models.PropertyFilter{Sort: "price; DROP TABLE properties"})
	if o != "ORDER BY created_at DESC, id" {
		t.Fatal(o)
	}
}
