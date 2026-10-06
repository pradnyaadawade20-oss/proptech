// Package signedurl makes short-lived, tamper-proof links to private files.
package signedurl

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

func secret() []byte {
	s := strings.TrimSpace(os.Getenv("SIGNED_URL_SECRET"))
	if s == "" {
		s = strings.TrimSpace(os.Getenv("JWT_SECRET"))
	}
	return []byte(s)
}

func mac(resource string, exp int64) string {
	m := hmac.New(sha256.New, secret())
	m.Write([]byte(resource + "|" + strconv.FormatInt(exp, 10)))
	return hex.EncodeToString(m.Sum(nil))
}

// Query returns "exp=...&sig=..." to append to the file URL.
func Query(resource string, ttl time.Duration) (string, error) {
	if len(secret()) < 16 {
		return "", errors.New("signing secret not configured")
	}
	exp := time.Now().Add(ttl).Unix()
	v := url.Values{}
	v.Set("exp", strconv.FormatInt(exp, 10))
	v.Set("sig", mac(resource, exp))
	return v.Encode(), nil
}

// Verify checks the signature and that the link has not expired.
func Verify(resource, expStr, sig string) bool {
	if len(secret()) < 16 {
		return false
	}
	exp, err := strconv.ParseInt(expStr, 10, 64)
	if err != nil || time.Now().Unix() > exp {
		return false
	}
	return hmac.Equal([]byte(mac(resource, exp)), []byte(sig))
}