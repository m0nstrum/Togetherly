// Package movies — поиск фильмов по Викиданным: чистые функции порта
// pocketbase/hotpath/movies.py (разбор записей, карточка в форме ответа
// poiskkino, нормализация запроса). Сеть и кэш — в usecase/movies.
//
// Зачем свой сервер, а не телефон: запись фильма в Викиданных весит сотни
// килобайт (справки к каждому утверждению). Сервер ужимает её до полутора
// килобайт и отдаёт клиенту список в форме poiskkino — клиент читает его
// прежним разбором (MovieResult.fromKinopoiskDoc).
package movies

// Жанры — таблицы из movies.py апстрима, чтобы не расходиться при мёржах.
//go:generate sh -c "python3 -I ../../../scripts/gen-movie-genres.py | gofmt > genres.go"

import (
	"encoding/json"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

// Langs — языки, на которых отдаём названия и жанры.
var Langs = []string{"ru", "en", "de", "fr", "es", "it", "pt", "zh"}

// zhVariants — китайский ярлык часто лежит под письмом или страной.
var zhVariants = []string{"zh-hans", "zh-cn", "zh-sg"}

// FetchLanguages — параметр languages для wbgetentities.
func FetchLanguages() string {
	return strings.Join(append(append([]string{"mul"}, Langs...), zhVariants...), "|")
}

// Lang — язык человека из запроса: два символа из Langs, иначе en.
func Lang(raw string) string {
	l := strings.ToLower(raw)
	if len(l) > 2 {
		l = l[:2]
	}
	for _, x := range Langs {
		if x == l {
			return l
		}
	}
	return "en"
}

// NormQuery — ключ кэша и строка поиска: без регистра, «ё», знаков и лишних
// пробелов. Знаки выбрасываются: CirrusSearch понимает часть из них как
// синтаксис (`-`, `"`, `:`). Короче двух символов — пусто.
func NormQuery(q string) string {
	s := strings.ToLower(q)
	s = strings.NewReplacer("ё", "е", "_", " ").Replace(s)
	var b strings.Builder
	for _, r := range s {
		if isWord(r) || unicode.IsSpace(r) {
			b.WriteRune(r)
		} else {
			b.WriteRune(' ')
		}
	}
	s = strings.Join(strings.Fields(b.String()), " ")
	if rs := []rune(s); len(rs) > 80 {
		s = strings.TrimSpace(string(rs[:80]))
	}
	if len([]rune(s)) < 2 {
		return ""
	}
	return s
}

// isWord — `\w` Питона: буква, цифра или подчёркивание.
func isWord(r rune) bool {
	return r == '_' || unicode.IsLetter(r) || unicode.IsNumber(r)
}

// Класс записи (P31) → тип, как его называет poiskkino и понимает клиент.
var kinds = map[string]string{
	"Q11424":     "movie",     // фильм
	"Q24869":     "movie",     // полнометражный фильм
	"Q24862":     "movie",     // короткометражный
	"Q506240":    "movie",     // телефильм
	"Q93204":     "movie",     // документальный
	"Q5398426":   "tv-series", // телесериал
	"Q1259759":   "tv-series", // мини-сериал
	"Q526877":    "tv-series", // веб-сериал
	"Q202866":    "cartoon",   // анимационный фильм
	"Q29168811":  "cartoon",   // полнометражный мультфильм
	"Q581714":    "animated-series",
	"Q117467246": "animated-series",
	"Q117467240": "animated-series",
	"Q63952888":  "anime", // аниме-сериал
	"Q20650540":  "anime", // аниме-фильм
}

// Анимация точнее «фильма»: мультфильм часто записан и тем, и другим.
var kindRank = map[string]int{"anime": 3, "animated-series": 2, "cartoon": 1}

var series = map[string]bool{"tv-series": true, "animated-series": true, "anime": true}

// adult — порнофильм: такое в ленте пары не предлагаем.
const adult = "Q185529"

// KindOf — тип по классам записи. Анимация сильнее, из фильма и сериала —
// первый по порядку.
func KindOf(classes []string) string {
	best, rank := "", -1
	for _, q := range classes {
		k, ok := kinds[q]
		if !ok {
			continue
		}
		if r := kindRank[k]; r > rank {
			best, rank = k, r
		}
	}
	return best
}

// searchTypes — фильтр поиска по классу, в порядке kinds из movies.py.
var searchTypes = func() string {
	order := []string{"Q11424", "Q24869", "Q24862", "Q506240", "Q93204", "Q5398426",
		"Q1259759", "Q526877", "Q202866", "Q29168811", "Q581714", "Q117467246",
		"Q117467240", "Q63952888", "Q20650540"}
	parts := make([]string, len(order))
	for i, q := range order {
		parts[i] = "P31=" + q
	}
	return strings.Join(parts, "|")
}()

// SearchParams — полнотекстовый поиск с фильтром по классу. Звёздочка к
// последнему слову находит недописанное, но ранжирует хуже, поэтому оба
// поиска идут вместе и точный главнее.
func SearchParams(q string, wildcard bool, limit int) map[string]string {
	text := q
	if wildcard {
		text += "*"
	}
	return map[string]string{
		"action": "query", "list": "search", "format": "json",
		"srsearch": text + " haswbstatement:" + searchTypes,
		"srlimit":  strconv.Itoa(limit), "srnamespace": "0", "srprop": "",
	}
}

// Wildcard — ставить ли звёздочку: с трёх букв она цепляет всё подряд.
func Wildcard(q string) bool {
	words := strings.Split(q, " ")
	return len([]rune(words[len(words)-1])) >= 4
}

var qidRe = regexp.MustCompile(`^Q\d+$`)

// SearchIDs — номера записей из ответа поиска.
func SearchIDs(payload []byte) []string {
	var p struct {
		Query struct {
			Search []struct {
				Title string `json:"title"`
			} `json:"search"`
		} `json:"query"`
	}
	if json.Unmarshal(payload, &p) != nil {
		return nil
	}
	var out []string
	for _, h := range p.Query.Search {
		if qidRe.MatchString(h.Title) {
			out = append(out, h.Title)
		}
	}
	return out
}

// Entity — запись Викиданных (только то, что читаем).
type Entity struct {
	ID      string                            `json:"id"`
	Missing *string                           `json:"missing"`
	Labels  map[string]struct{ Value string } `json:"labels"`
	Claims  map[string][]claim                `json:"claims"`
}

type claim struct {
	Rank     string `json:"rank"`
	Mainsnak struct {
		Datavalue struct {
			Value json.RawMessage `json:"value"`
		} `json:"datavalue"`
	} `json:"mainsnak"`
}

func (e Entity) values(prop string) []json.RawMessage {
	var out []json.RawMessage
	for _, c := range e.Claims[prop] {
		if c.Rank == "deprecated" || len(c.Mainsnak.Datavalue.Value) == 0 {
			continue
		}
		out = append(out, c.Mainsnak.Datavalue.Value)
	}
	return out
}

func (e Entity) ids(prop string) []string {
	var out []string
	for _, v := range e.values(prop) {
		var x struct {
			ID string `json:"id"`
		}
		if json.Unmarshal(v, &x) == nil && x.ID != "" {
			out = append(out, x.ID)
		}
	}
	return out
}

func (e Entity) strings(prop string) []string {
	var out []string
	for _, v := range e.values(prop) {
		var s string
		if json.Unmarshal(v, &s) == nil && s != "" {
			out = append(out, s)
		}
	}
	return out
}

var yearRe = regexp.MustCompile(`^\+(\d{4})-`)

// years — `+2014-10-26T00:00:00Z` → 2014. До нашей эры кино не касается.
func (e Entity) years(prop string) []int {
	var out []int
	for _, v := range e.values(prop) {
		var t struct {
			Time string `json:"time"`
		}
		if json.Unmarshal(v, &t) != nil {
			continue
		}
		if m := yearRe.FindStringSubmatch(t.Time); m != nil {
			if y, _ := strconv.Atoi(m[1]); y > 0 {
				out = append(out, y)
			}
		}
	}
	return out
}

// LabelMap — ярлыки записи, китайский сведён к zh.
func (e Entity) LabelMap() map[string]string {
	out := map[string]string{}
	for lang, v := range e.Labels {
		if v.Value != "" {
			out[lang] = v.Value
		}
	}
	if out["zh"] == "" {
		for _, code := range zhVariants {
			if out[code] != "" {
				out["zh"] = out[code]
				break
			}
		}
	}
	return out
}

// Title — оригинальное название (P1476) на своём языке.
type Title struct {
	Lang string `json:"l"`
	Text string `json:"t"`
}

// Compact — то немногое, что нужно карточке фильма. Kind пуст — запись не
// фильм (страна, например).
type Compact struct {
	QID    string            `json:"qid"`
	Kind   string            `json:"kind,omitempty"`
	Labels map[string]string `json:"labels,omitempty"`
	Titles []Title           `json:"titles,omitempty"`
	KP     int               `json:"kp,omitempty"`
	IMDb   string            `json:"imdb,omitempty"`
	Year   int               `json:"year,omitempty"`
	Start  int               `json:"start,omitempty"`
	End    int               `json:"end,omitempty"`
	Genres []string          `json:"genres,omitempty"`
	// Country — QID страны производства.
	Country string `json:"country,omitempty"`
	// Poster — имя файла на Commons (P3383).
	Poster string `json:"poster,omitempty"`
	Adult  bool   `json:"adult,omitempty"`
}

var (
	digitsRe = regexp.MustCompile(`^\d+$`)
	imdbRe   = regexp.MustCompile(`^tt\d+$`)
)

// CompactEntity — полная запись → Compact. ok=false — записи нет.
func CompactEntity(e Entity) (Compact, bool) {
	if e.Missing != nil {
		return Compact{}, false
	}
	classes := e.ids("P31")
	c := Compact{QID: e.ID, Kind: KindOf(classes), Labels: e.LabelMap()}
	if c.Kind == "" {
		return c, true
	}
	for _, v := range e.strings("P2603") {
		if digitsRe.MatchString(v) {
			c.KP, _ = strconv.Atoi(v)
			break
		}
	}
	for _, v := range e.strings("P345") {
		if imdbRe.MatchString(v) {
			c.IMDb = v
			break
		}
	}
	released, starts, ends := e.years("P577"), e.years("P580"), e.years("P582")
	switch {
	case len(released) > 0:
		c.Year = minOf(released)
	case len(starts) > 0:
		c.Year = minOf(starts)
	}
	if len(starts) > 0 {
		c.Start = minOf(starts)
	}
	if len(ends) > 0 {
		c.End = maxOf(ends)
	}

	genresQ := e.ids("P136")
	for _, q := range genresQ {
		if g, ok := genreOf[q]; ok && !contains(c.Genres, g) {
			c.Genres = append(c.Genres, g)
		}
	}
	if len(c.Genres) > 3 {
		c.Genres = c.Genres[:3]
	}

	seen := map[string]bool{}
	for _, v := range e.values("P1476") {
		var t struct {
			Text     string `json:"text"`
			Language string `json:"language"`
		}
		if json.Unmarshal(v, &t) == nil && t.Text != "" && !seen[t.Language] {
			seen[t.Language] = true
			c.Titles = append(c.Titles, Title{Lang: t.Language, Text: t.Text})
		}
	}
	if p := e.strings("P3383"); len(p) > 0 {
		c.Poster = p[0]
	}
	if cs := e.ids("P495"); len(cs) > 0 {
		c.Country = cs[0]
	}
	c.Adult = contains(classes, adult) || contains(genresQ, adult)
	return c, true
}

// Doc — карточка в форме ответа poiskkino.
type Doc struct {
	ID              int            `json:"id"`
	Name            string         `json:"name"`
	Type            string         `json:"type"`
	AlternativeName string         `json:"alternativeName,omitempty"`
	Year            int            `json:"year,omitempty"`
	ReleaseYears    []ReleaseYears `json:"releaseYears,omitempty"`
	Poster          *Poster        `json:"poster,omitempty"`
	Link            string         `json:"link,omitempty"`
	Genres          []Named        `json:"genres,omitempty"`
	Countries       []Named        `json:"countries,omitempty"`
}

// ReleaseYears — годы сериала; End nil — ещё идёт.
type ReleaseYears struct {
	Start int  `json:"start"`
	End   *int `json:"end"`
}

// Poster — адрес картинки.
type Poster struct {
	URL        string `json:"url"`
	PreviewURL string `json:"previewUrl"`
}

// Named — жанр или страна.
type Named struct {
	Name string `json:"name"`
}

// pickLabel — ярлык на языке, иначе общий (mul), английский, русский, любой.
// mul — имена, которые не переводятся: у «Друзей» английского ярлыка нет.
func pickLabel(labels map[string]string, lang string) string {
	for _, code := range []string{lang, "mul", "en", "ru"} {
		if labels[code] != "" {
			return labels[code]
		}
	}
	keys := make([]string, 0, len(labels))
	for k := range labels {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		if labels[k] != "" {
			return labels[k]
		}
	}
	return ""
}

// readable — название прочтёт человек без иероглифов: латиница, кириллица,
// цифры, знаки. Японское «NARUTO -ナルト-» у аниме ему ничего не скажет.
func readable(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		switch {
		case unicode.IsSpace(r), r < 0x80 && (unicode.IsLetter(r) || unicode.IsDigit(r)),
			r >= 0xC0 && r <= 0x24F, r >= 0x400 && r <= 0x4FF, !isWord(r):
		default:
			return false
		}
	}
	return true
}

// DocFromCompact — карточка на языке человека. countries — ярлыки стран по QID.
func DocFromCompact(c Compact, lang string, countries map[string]map[string]string) Doc {
	lang = Lang(lang)
	titleIn := func(l string) string {
		for _, t := range c.Titles {
			if t.Lang == l {
				return t.Text
			}
		}
		return ""
	}
	name := c.Labels[lang]
	if name == "" {
		name = titleIn(lang)
	}
	if name == "" {
		name = pickLabel(c.Labels, lang)
	}
	if name == "" && len(c.Titles) > 0 {
		name = c.Titles[0].Text
	}
	original := ""
	for _, t := range c.Titles {
		if readable(t.Text) {
			original = t.Text
			break
		}
	}
	if original == "" {
		original = c.Labels["en"]
	}
	if original == "" {
		original = c.Labels["mul"]
	}

	kind := c.Kind
	if kind == "" {
		kind = "movie"
	}
	d := Doc{ID: c.KP, Name: name, Type: kind, Year: c.Year}
	if original != "" && original != name {
		d.AlternativeName = original
	}
	if series[kind] && c.Start > 0 {
		ry := ReleaseYears{Start: c.Start}
		if c.End > 0 {
			end := c.End
			ry.End = &end
		}
		d.ReleaseYears = []ReleaseYears{ry}
	}

	if c.KP > 0 {
		u := "https://st.kp.yandex.net/images/film_iphone/iphone360_" + strconv.Itoa(c.KP) + ".jpg"
		d.Poster = &Poster{URL: u, PreviewURL: u}
		d.Link = "https://www.kinopoisk.ru/film/" + strconv.Itoa(c.KP) + "/"
	} else {
		if c.Poster != "" {
			u := "https://commons.wikimedia.org/wiki/Special:FilePath/" +
				quote(strings.ReplaceAll(c.Poster, " ", "_")) + "?width=360"
			d.Poster = &Poster{URL: u, PreviewURL: u}
		}
		switch {
		case c.IMDb != "":
			d.Link = "https://www.imdb.com/title/" + c.IMDb + "/"
		case c.QID != "":
			d.Link = "https://www.wikidata.org/wiki/" + c.QID
		}
	}

	for _, g := range c.Genres {
		names, ok := genreNames[g]
		if !ok {
			continue
		}
		n := names[lang]
		if n == "" {
			n = names["en"]
		}
		d.Genres = append(d.Genres, Named{Name: n})
	}
	if l := pickLabel(countries[c.Country], lang); c.Country != "" && l != "" {
		d.Countries = []Named{{Name: l}}
	}
	return d
}

// quote — urllib.parse.quote: всё, кроме букв, цифр и `_.-~/`, — в %XX.
func quote(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		ch := s[i]
		if ch < 0x80 && (ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z' || ch >= '0' && ch <= '9' ||
			strings.IndexByte("_.-~/", ch) >= 0) {
			b.WriteByte(ch)
			continue
		}
		b.WriteByte('%')
		b.WriteByte(hex[ch>>4])
		b.WriteByte(hex[ch&15])
	}
	return b.String()
}

func minOf(xs []int) int {
	m := xs[0]
	for _, x := range xs[1:] {
		m = min(m, x)
	}
	return m
}

func maxOf(xs []int) int {
	m := xs[0]
	for _, x := range xs[1:] {
		m = max(m, x)
	}
	return m
}

func contains(xs []string, x string) bool {
	for _, y := range xs {
		if y == x {
			return true
		}
	}
	return false
}
