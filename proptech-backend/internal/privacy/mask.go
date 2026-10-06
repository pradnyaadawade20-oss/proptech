// Package privacy masks personal contact details shown to other users.
package privacy

import "strings"

// MaskPhone keeps the first 2 and last 2 digits: 9876543210 -> 98XXXXXX10.
func MaskPhone(p string) string {
	p = strings.TrimSpace(p)
	if p == "" {
		return ""
	}
	r := []rune(p)
	if len(r) <= 4 {
		return strings.Repeat("X", len(r))
	}
	for i := 2; i < len(r)-2; i++ {
		if r[i] >= '0' && r[i] <= '9' {
			r[i] = 'X'
		}
	}
	return string(r)
}

// MaskEmail: rahul@gmail.com -> r***@gmail.com.
func MaskEmail(e string) string {
	e = strings.TrimSpace(e)
	at := strings.LastIndex(e, "@")
	if at <= 0 {
		return ""
	}
	return e[:1] + "***" + e[at:]
}