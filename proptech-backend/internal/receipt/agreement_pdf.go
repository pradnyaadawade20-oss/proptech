package receipt

// Rental agreement PDF (multi-page A4), built with the standard library only,
// same approach as receipt.go. Drawn signatures (PNG) are embedded as images,
// typed signatures are written in an italic font.

import (
	"bytes"
	"compress/zlib"
	"encoding/base64"
	"fmt"
	"image/png"
	"strings"
)

type AgreementData struct {
	AgreementID     string
	PropertyTitle   string
	PropertyAddress string
	OwnerName       string
	TenantName      string
	AgentName       string

	MonthlyRent      float64
	SecurityDeposit  float64
	StartDate        string // already formatted, e.g. "1 Nov 2026"
	EndDate          string
	DurationMonths   int
	RentDueDay       int
	NoticePeriodDays int
	Terms            string

	OwnerSignType  string // "draw" | "type"
	OwnerSignData  string // base64 PNG or the typed name
	OwnerSignedAt  string
	TenantSignType string
	TenantSignData string
	TenantSignedAt string
}

type agImage struct {
	w, h int
	data []byte // zlib-compressed RGB
}

type agDoc struct {
	pages  []*bytes.Buffer
	cur    *bytes.Buffer
	y      int
	images []agImage
}

func (d *agDoc) newPage() {
	d.cur = &bytes.Buffer{}
	d.pages = append(d.pages, d.cur)
	d.y = 800
}

func (d *agDoc) text(font string, size, x, y int, s string) {
	fmt.Fprintf(d.cur, "BT /%s %d Tf %d %d Td (%s) Tj ET\n", font, size, x, y, esc(s))
}

func (d *agDoc) rule(x1, y1, x2, y2 int) {
	fmt.Fprintf(d.cur, "0.85 0.88 0.92 RG 0.8 w %d %d m %d %d l S\n", x1, y1, x2, y2)
}

// ensure starts a new page when fewer than h points are left.
func (d *agDoc) ensure(h int) {
	if d.y-h < 70 {
		d.newPage()
	}
}

func agWrap(s string, max int) []string {
	var out []string
	for _, para := range strings.Split(s, "\n") {
		para = clean(para, 1<<20)
		if para == "" {
			out = append(out, "")
			continue
		}
		line := ""
		for _, w := range strings.Fields(para) {
			for len(w) > max { // very long word: hard split
				if line != "" {
					out = append(out, line)
					line = ""
				}
				out = append(out, w[:max])
				w = w[max:]
			}
			switch {
			case line == "":
				line = w
			case len(line)+1+len(w) <= max:
				line += " " + w
			default:
				out = append(out, line)
				line = w
			}
		}
		if line != "" {
			out = append(out, line)
		}
	}
	return out
}

func (d *agDoc) section(title string) {
	d.ensure(50)
	d.y -= 12
	d.text("F2", 13, 50, d.y, title)
	d.rule(50, d.y-6, 545, d.y-6)
	d.y -= 26
}

func (d *agDoc) kv(label, value string) {
	lines := agWrap(value, 62)
	if len(lines) == 0 {
		lines = []string{"-"}
	}
	d.ensure(len(lines)*14 + 12)
	d.text("F2", 11, 50, d.y, label)
	for i, l := range lines {
		d.text("F1", 11, 210, d.y-i*14, l)
	}
	d.y -= len(lines)*14 + 8
}

func agLoadSignature(data string) (agImage, bool) {
	data = strings.TrimSpace(data)
	if strings.HasPrefix(data, "data:") {
		if i := strings.Index(data, ","); i >= 0 {
			data = data[i+1:]
		}
	}
	raw, err := base64.StdEncoding.DecodeString(data)
	if err != nil {
		return agImage{}, false
	}
	img, err := png.Decode(bytes.NewReader(raw))
	if err != nil {
		return agImage{}, false
	}
	b := img.Bounds()
	w, h := b.Dx(), b.Dy()
	if w < 1 || h < 1 {
		return agImage{}, false
	}
	step := 1
	for w/step > 500 {
		step++
	}
	ow, oh := w/step, h/step
	if ow < 1 || oh < 1 {
		return agImage{}, false
	}
	rgb := make([]byte, 0, ow*oh*3)
	for y := 0; y < oh; y++ {
		for x := 0; x < ow; x++ {
			r, g, bl, a := img.At(b.Min.X+x*step, b.Min.Y+y*step).RGBA()
			// colours are alpha-premultiplied: composite over white paper
			rgb = append(rgb,
				byte((r+(65535-a))>>8),
				byte((g+(65535-a))>>8),
				byte((bl+(65535-a))>>8))
		}
	}
	var zb bytes.Buffer
	zw := zlib.NewWriter(&zb)
	zw.Write(rgb)
	zw.Close()
	return agImage{w: ow, h: oh, data: zb.Bytes()}, true
}

// signature draws one signature block with its left edge at x.
func (d *agDoc) signature(x int, role, name, kind, data, signedAt string) {
	top := d.y
	d.text("F2", 11, x, top, role)
	d.text("F1", 10, x, top-15, clean(name, 30))

	drawn := false
	if kind == "draw" {
		if im, ok := agLoadSignature(data); ok {
			d.images = append(d.images, im)
			maxW, maxH := 170.0, 60.0
			sc := maxW / float64(im.w)
			if s2 := maxH / float64(im.h); s2 < sc {
				sc = s2
			}
			w, h := float64(im.w)*sc, float64(im.h)*sc
			fmt.Fprintf(d.cur, "q %.1f 0 0 %.1f %d %.1f cm /Im%d Do Q\n", w, h, x, float64(top-25)-h, len(d.images))
			drawn = true
		}
	}
	if !drawn {
		d.text("F3", 20, x, top-50, clean(data, 24))
	}
	fmt.Fprintf(d.cur, "0.6 0.6 0.6 RG 0.8 w %d %d m %d %d l S\n", x, top-95, x+200, top-95)
	d.text("F1", 9, x, top-108, "Digitally signed on "+clean(signedAt, 40))
}

// BuildAgreement returns the agreement PDF bytes.
func BuildAgreement(a AgreementData) []byte {
	d := &agDoc{}
	d.newPage()

	// Header band (first page only)
	d.cur.WriteString("0.082 0.333 0.541 rg 0 742 595 100 re f\n1 1 1 rg\n")
	d.text("F2", 24, 50, 792, "RENTAL AGREEMENT")
	d.text("F1", 11, 50, 768, "Agreement ID: "+clean(a.AgreementID, 50))
	d.text("F1", 11, 50, 752, "Status: Signed by both parties")
	d.cur.WriteString("0 0 0 rg\n")
	d.y = 715

	intro := fmt.Sprintf("This rental agreement is made between %s (the Owner) and %s (the Tenant) for the property described below. Both parties have agreed to the terms in this document and have signed it digitally on PropTech.",
		clean(a.OwnerName, 60), clean(a.TenantName, 60))
	for _, l := range agWrap(intro, 92) {
		d.text("F1", 10, 50, d.y, l)
		d.y -= 14
	}

	d.section("Parties")
	d.kv("Owner (Landlord)", a.OwnerName)
	d.kv("Tenant", a.TenantName)
	if a.AgentName != "" {
		d.kv("Agent (Broker)", a.AgentName)
	d.kv("Brokerage", "Settled separately between the Tenant and the Agent; not part of this agreement")
	}

	d.section("Property")
	d.kv("Property", a.PropertyTitle)
	if a.PropertyAddress != "" {
		d.kv("Address", a.PropertyAddress)
	}

	d.section("Rental terms")
	d.kv("Monthly rent", money(a.MonthlyRent))
	d.kv("Security deposit", money(a.SecurityDeposit))
	if a.StartDate != "" {
		d.kv("Lease start", a.StartDate)
	}
	if a.EndDate != "" {
		d.kv("Lease end", a.EndDate)
	}
	if a.DurationMonths > 0 {
		d.kv("Duration", fmt.Sprintf("%d months", a.DurationMonths))
	}
	if a.RentDueDay > 0 {
		d.kv("Rent due", fmt.Sprintf("Day %d of every month", a.RentDueDay))
	}
	if a.NoticePeriodDays > 0 {
		d.kv("Notice period", fmt.Sprintf("%d days", a.NoticePeriodDays))
	}

	if strings.TrimSpace(a.Terms) != "" {
		d.section("Terms and conditions")
		for _, l := range agWrap(a.Terms, 92) {
			d.ensure(14)
			if l != "" {
				d.text("F1", 10, 50, d.y, l)
			}
			d.y -= 14
		}
	}

	d.section("Signatures")
	d.ensure(130)
	d.signature(50, "Owner", a.OwnerName, a.OwnerSignType, a.OwnerSignData, a.OwnerSignedAt)
	d.signature(320, "Tenant", a.TenantName, a.TenantSignType, a.TenantSignData, a.TenantSignedAt)
	d.y -= 125

	// Footer on every page
	for i, p := range d.pages {
		fmt.Fprintf(p, "0 0 0 rg BT /F1 8 Tf 50 40 Td (%s) Tj ET\n",
			esc(fmt.Sprintf("Generated by PropTech  |  Agreement %s  |  Page %d of %d", clean(a.AgreementID, 40), i+1, len(d.pages))))
	}

	return d.assemble()
}

// assemble turns the drawn pages (and signature images) into the final PDF bytes.
func (d *agDoc) assemble() []byte {
	nImg := len(d.images)
	imgStart := 6
	pageStart := imgStart + nImg

	var objs [][]byte
	add := func(s string) { objs = append(objs, []byte(s)) }

	add("<< /Type /Catalog /Pages 2 0 R >>")
	var kids strings.Builder
	for i := range d.pages {
		fmt.Fprintf(&kids, "%d 0 R ", pageStart+2*i)
	}
	add(fmt.Sprintf("<< /Type /Pages /Kids [%s] /Count %d >>", kids.String(), len(d.pages)))
	add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
	add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")
	add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique /Encoding /WinAnsiEncoding >>")

	xobj := ""
	for i, im := range d.images {
		var b bytes.Buffer
		fmt.Fprintf(&b, "<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length %d >>\nstream\n", im.w, im.h, len(im.data))
		b.Write(im.data)
		b.WriteString("\nendstream")
		objs = append(objs, b.Bytes())
		xobj += fmt.Sprintf("/Im%d %d 0 R ", i+1, imgStart+i)
	}
	res := "/Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >>"
	if xobj != "" {
		res += " /XObject << " + xobj + ">>"
	}

	for i, p := range d.pages {
		add(fmt.Sprintf("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents %d 0 R /Resources << %s >> >>", pageStart+2*i+1, res))
		add(fmt.Sprintf("<< /Length %d >>\nstream\n%sendstream", p.Len(), p.String()))
	}

	var out bytes.Buffer
	out.WriteString("%PDF-1.4\n")
	offsets := make([]int, len(objs))
	for i, o := range objs {
		offsets[i] = out.Len()
		fmt.Fprintf(&out, "%d 0 obj\n", i+1)
		out.Write(o)
		out.WriteString("\nendobj\n")
	}
	xref := out.Len()
	fmt.Fprintf(&out, "xref\n0 %d\n", len(objs)+1)
	out.WriteString("0000000000 65535 f \n")
	for _, off := range offsets {
		fmt.Fprintf(&out, "%010d 00000 n \n", off)
	}
	fmt.Fprintf(&out, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", len(objs)+1, xref)
	return out.Bytes()
}