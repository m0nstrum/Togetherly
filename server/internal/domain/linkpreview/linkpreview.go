// Package linkpreview — карточка товара по HTML страницы: название, картинка,
// магазин, цена. Порт разбора из pocketbase/pb_hooks/link_preview.pb.js один
// в один, чтобы ответ клиенту не изменился.
package linkpreview

import (
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Preview — ответ /api/link/preview без поля success.
type Preview struct {
	Title    string `json:"title"`
	Image    string `json:"image"`
	Shop     string `json:"shop"`
	Price    int    `json:"price"`
	Currency string `json:"currency"`
}

// Parse разбирает html страницы pageURL.
func Parse(html, pageURL string) Preview {
	u, _ := url.Parse(pageURL)
	host := ""
	if u != nil {
		host = strings.ToLower(u.Hostname())
	}

	title := unescape(meta(html, "og:title", "twitter:title"))
	if title == "" {
		if m := titleRe.FindStringSubmatch(html); m != nil {
			title = unescape(m[1])
		}
	}
	image := unescape(meta(html, "og:image", "og:image:secure_url", "twitter:image"))
	site := unescape(meta(html, "og:site_name"))
	if site == "" {
		site = strings.TrimPrefix(host, "www.")
	}
	price := unescape(meta(html, "product:price:amount", "og:price:amount", "price", "twitter:data1"))
	currency := unescape(meta(html, "product:price:currency", "og:price:currency", "priceCurrency"))
	// JSON-LD Product — у крупных магазинов цена лежит именно там.
	if price == "" {
		if m := ldPriceRe.FindStringSubmatch(html); m != nil {
			price = m[1]
		}
	}
	if currency == "" {
		if m := ldCurrencyRe.FindStringSubmatch(html); m != nil {
			currency = m[1]
		}
	}

	cur := strings.ToUpper(currency)
	if cur == "" && rubRe.MatchString(head(html, 60000)) {
		cur = "RUB"
	}
	sign := signs[cur]
	if sign == "" {
		sign = cur
	}

	if image != "" && !strings.HasPrefix(image, "//") && !strings.HasPrefix(image, "http") && u != nil {
		origin := u.Scheme + "://" + host
		if strings.HasPrefix(image, "/") {
			image = origin + image
		} else {
			image = origin + "/" + image
		}
	}
	if strings.HasPrefix(image, "//") {
		image = "https:" + image
	}

	return Preview{
		Title:    cut(title, 120),
		Image:    cut(image, 500),
		Shop:     cut(site, 80),
		Price:    amount(price),
		Currency: sign,
	}
}

var (
	titleRe      = regexp.MustCompile(`(?is)<title[^>]*>(.{0,300}?)</title>`)
	ldPriceRe    = regexp.MustCompile(`(?i)"price"\s*:\s*"?([0-9][0-9\s.,]*)"?`)
	ldCurrencyRe = regexp.MustCompile(`(?i)"priceCurrency"\s*:\s*"([A-Za-z]{3})"`)
	rubRe        = regexp.MustCompile(`(?i)₽|руб`)
	centsRe      = regexp.MustCompile(`[.,](\d{1,2})$`)
	spaceRe      = regexp.MustCompile(`\s+`)
	signs        = map[string]string{"RUB": "₽", "USD": "$", "EUR": "€", "KZT": "₸", "BYN": "Br", "UAH": "₴"}
)

func meta(html string, names ...string) string {
	for _, n := range names {
		q := regexp.QuoteMeta(n)
		for _, p := range []string{
			`(?i)<meta[^>]+(?:property|name|itemprop)\s*=\s*["']` + q + `["'][^>]*content\s*=\s*["']([^"']*)["']`,
			`(?i)<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]*(?:property|name|itemprop)\s*=\s*["']` + q + `["']`,
		} {
			if m := regexp.MustCompile(p).FindStringSubmatch(html); m != nil && m[1] != "" {
				return m[1]
			}
		}
	}
	return ""
}

var entities = strings.NewReplacer(
	"&quot;", `"`, "&#39;", "'", "&#039;", "'", "&apos;", "'",
	"&nbsp;", " ", "&lt;", "<", "&gt;", ">",
)

func unescape(s string) string {
	s = entities.Replace(s)
	s = strings.ReplaceAll(s, "&amp;", "&")
	return strings.TrimSpace(spaceRe.ReplaceAllString(s, " "))
}

// amount — целые единицы: «12 990,00» → 12990, «от 1 299 ₽» → 1299.
func amount(price string) int {
	if price == "" {
		return 0
	}
	var b strings.Builder
	for _, r := range price {
		if (r >= '0' && r <= '9') || r == '.' || r == ',' {
			b.WriteRune(r)
		}
	}
	digits := centsRe.ReplaceAllString(b.String(), "")
	plain := strings.NewReplacer(".", "", ",", "").Replace(digits)
	n, err := strconv.Atoi(plain)
	if err != nil || n <= 0 || n >= 1_000_000_000 {
		return 0
	}
	return n
}

func cut(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	return string([]rune(s)[:n])
}

func head(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
