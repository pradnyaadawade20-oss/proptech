package handlers

import (
	"fmt"
	"html"
	"net/http"
	"net/url"
	"os"
	"strings"

	"proptech-backend/internal/repository"

	"github.com/gin-gonic/gin"
)

func androidPackage() string {
	if p := strings.TrimSpace(os.Getenv("ANDROID_PACKAGE")); p != "" {
		return p
	}
	return "com.example.proptech_app"
}

// GET /.well-known/assetlinks.json
// Lets Android verify that this domain belongs to the app, so tapping a share link opens the
// app directly. Set ANDROID_SHA256_CERT_FINGERPRINTS (comma separated, from Play Console
// "App signing" and/or your upload / debug key) and optionally ANDROID_PACKAGE.
func AssetLinks(c *gin.Context) {
	var fps []string
	for _, f := range strings.Split(os.Getenv("ANDROID_SHA256_CERT_FINGERPRINTS"), ",") {
		if f = strings.ToUpper(strings.TrimSpace(f)); f != "" {
			fps = append(fps, f)
		}
	}
	if fps == nil {
		fps = []string{}
	}
	c.Header("Cache-Control", "public, max-age=3600")
	c.JSON(http.StatusOK, []gin.H{{
		"relation": []string{"delegate_permission/common.handle_all_urls"},
		"target": gin.H{
			"namespace":                "android_app",
			"package_name":             androidPackage(),
			"sha256_cert_fingerprints": fps,
		},
	}})
}

// GET /o/:token  (public)
// The page behind the share link. With the app installed and the domain verified, Android never
// shows this page: the link opens the app. Otherwise (app missing, or opened on a PC) the owner
// lands here and gets an "Open in app" and an "Install app" button.
func (h *LandlordInviteHandler) InviteLandingPage(c *gin.Context) {
	token := c.Param("token")
	if !repository.ValidInviteToken(token) {
		c.String(http.StatusNotFound, "This link is not valid.")
		return
	}

	heading := "Approve your property listing"
	detail := "A broker wants to list your property on PropTech. Open the app to review the details and approve."
	if inv, err := h.repo.GetByToken(c.Request.Context(), token); err == nil {
		who := inv.BrokerName
		if who == "" {
			who = "A broker"
		}
		detail = fmt.Sprintf("%s wants to list \"%s\" on PropTech. Open the app, log in or sign up, review the details and approve. It goes live only after you approve.", who, inv.PropertyTitle)
		switch inv.Status {
		case "accepted":
			detail = fmt.Sprintf("\"%s\" is already approved and live.", inv.PropertyTitle)
		case "expired", "cancelled", "declined":
			detail = "This invitation is no longer active. Ask the broker to send a new link."
		}
	}

	base := baseURL(c)
	host := ""
	if u, err := url.Parse(base); err == nil {
		host = u.Host
	}

	installURL := strings.TrimSpace(os.Getenv("PLAY_STORE_URL"))
	if installURL == "" {
		installURL = strings.TrimSpace(os.Getenv("APK_DOWNLOAD_URL"))
	}

	fallback := installURL
	if fallback == "" {
		fallback = base + "/o/" + token
	}
	// Android Chrome: open the app if it is installed, otherwise go to the install page.
	intentURL := fmt.Sprintf("intent://%s/o/%s#Intent;scheme=https;package=%s;S.browser_fallback_url=%s;end",
		host, token, androidPackage(), url.QueryEscape(fallback))

	installBtn := ""
	if installURL != "" {
		installBtn = fmt.Sprintf(`<a class="btn ghost" href="%s">Install the PropTech app</a>
<p class="hint">After installing, sign up, then tap this link again.</p>`, html.EscapeString(installURL))
	} else {
		installBtn = `<p class="hint">Don't have the app? Ask the broker for the download link, install it, sign up, then tap this link again.</p>`
	}

	c.Header("Content-Type", "text/html; charset=utf-8")
	c.Header("Cache-Control", "no-store")
	c.Header("Referrer-Policy", "no-referrer")
	c.String(http.StatusOK, `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>PropTech - %s</title>
<meta property="og:type" content="website">
<meta property="og:title" content="PropTech - %s">
<meta property="og:description" content="%s">
<style>
body{font-family:system-ui,sans-serif;background:#f6f7fb;margin:0;padding:24px;color:#1b1f3b}
.card{max-width:440px;margin:40px auto;background:#fff;border-radius:16px;padding:24px;box-shadow:0 4px 20px rgba(0,0,0,.08)}
h1{font-size:20px;margin:0 0 12px}p{line-height:1.5;color:#4a4f6a}
.btn{display:block;text-align:center;padding:14px;border-radius:12px;background:#4f46e5;color:#fff;text-decoration:none;font-weight:600;margin-top:16px}
.btn.ghost{background:#fff;color:#4f46e5;border:2px solid #4f46e5}
.hint{font-size:13px;color:#7a7f99}
</style></head><body><div class="card">
<h1>%s</h1><p>%s</p>
<a class="btn" href="%s">Open in the PropTech app</a>
%s
</div></body></html>`,
		html.EscapeString(heading), html.EscapeString(heading), html.EscapeString(detail),
		html.EscapeString(heading), html.EscapeString(detail),
		html.EscapeString(intentURL), installBtn)
}