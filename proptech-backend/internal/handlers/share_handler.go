package handlers

import (
	"fmt"
	"html"
	"net/http"

	"github.com/gin-gonic/gin"
)

// GET /p/:id  — public share page (WhatsApp/Telegram preview ke liye OG tags)
func (h *PropertyHandler) SharePage(c *gin.Context) {
	p, err := h.repo.GetByID(c.Request.Context(), c.Param("id"))
	if err != nil {
		c.String(http.StatusNotFound, "Listing not found")
		return
	}

	base := baseURL(c)
	title := html.EscapeString(p.Title)
	desc := html.EscapeString(fmt.Sprintf("₹%.0f%s • %s", p.Price, p.PriceUnit, p.Location))
	img := p.ImageURL
	if img == "" || img[0] == '/' {
		img = fmt.Sprintf("%s/api/properties/%s/image", base, p.ID)
	}
	img = html.EscapeString(img)

	c.Header("Content-Type", "text/html; charset=utf-8")
	c.String(http.StatusOK, `<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>%s</title>
<meta property="og:type" content="website">
<meta property="og:title" content="%s">
<meta property="og:description" content="%s">
<meta property="og:image" content="%s">
<meta name="twitter:card" content="summary_large_image">
</head><body style="font-family:sans-serif;max-width:480px;margin:24px auto;padding:0 16px">
<img src="%s" style="width:100%%;border-radius:12px" alt="">
<h2>%s</h2><p>%s</p>
<p>Open the PropTech app to see full details.</p>
</body></html>`, title, title, desc, img, img, title, desc)
}
