package linkpreview_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/domain/linkpreview"
)

func TestParse(t *testing.T) {
	cases := []struct {
		name string
		html string
		url  string
		want linkpreview.Preview
	}{
		{
			name: "og-теги и цена с копейками",
			html: `<meta property="og:title" content="Кружка &amp; блюдце"><meta content="/img/a.jpg" property="og:image">
				<meta property="product:price:amount" content="12 990,00"><meta property="product:price:currency" content="RUB">
				<meta property="og:site_name" content="Магазин">`,
			url:  "https://shop.example.org/p/1",
			want: linkpreview.Preview{Title: "Кружка & блюдце", Image: "https://shop.example.org/img/a.jpg", Shop: "Магазин", Price: 12990, Currency: "₽"},
		},
		{
			name: "title и JSON-LD",
			html: `<title> Книга </title><script>{"price": "1299.5", "priceCurrency":"usd"}</script>
				<meta name="twitter:image" content="//cdn.example.org/b.png">`,
			url:  "https://www.books.example.org/x",
			want: linkpreview.Preview{Title: "Книга", Image: "https://cdn.example.org/b.png", Shop: "books.example.org", Price: 1299, Currency: "$"},
		},
		{
			name: "рубль по знаку на странице",
			html: `<title>Чайник</title><span>от 1 299 ₽</span><meta itemprop="price" content="от 1 299">`,
			url:  "https://t.example.org/",
			want: linkpreview.Preview{Title: "Чайник", Shop: "t.example.org", Price: 1299, Currency: "₽"},
		},
		{
			name: "пусто",
			url:  "https://e.example.org/",
			want: linkpreview.Preview{Shop: "e.example.org"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, tc.want, linkpreview.Parse(tc.html, tc.url))
		})
	}
}
