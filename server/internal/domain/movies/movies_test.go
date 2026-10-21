package movies

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Образец ответа снят автором с живого API; тот же файл читают тесты
// апстрима (pocketbase/hotpath/test_movies.py).
const fixture = "../../../../pocketbase/hotpath/fixtures/wikidata_sample.json"

type sample struct {
	Entities struct {
		Entities map[string]Entity `json:"entities"`
	} `json:"entities"`
	Search json.RawMessage `json:"search"`
}

func load(t *testing.T) sample {
	t.Helper()
	raw, err := os.ReadFile(fixture)
	require.NoError(t, err)
	var s sample
	require.NoError(t, json.Unmarshal(raw, &s))
	return s
}

func compact(t *testing.T, s sample, qid string) Compact {
	t.Helper()
	e, ok := s.Entities.Entities[qid]
	require.True(t, ok, qid)
	c, ok := CompactEntity(e)
	require.True(t, ok)
	return c
}

func TestNormQuery(t *testing.T) {
	t.Run("регистр и пробелы", func(t *testing.T) {
		assert.Equal(t, "счастливого дня смерти", NormQuery("  Счастливого   ДНЯ смерти "))
	})
	t.Run("ё не плодит второй ключ", func(t *testing.T) {
		assert.Equal(t, NormQuery("Елки"), NormQuery("Ёлки"))
	})
	t.Run("кавычки и знаки", func(t *testing.T) {
		assert.Equal(t, NormQuery("Матрица"), NormQuery("«Матрица»"))
		assert.Equal(t, "a b", NormQuery(`a -"b:`))
	})
	t.Run("короткий пустой", func(t *testing.T) {
		assert.Empty(t, NormQuery("а"))
		assert.Empty(t, NormQuery("   "))
	})
	t.Run("длина ограничена", func(t *testing.T) {
		assert.LessOrEqual(t, len([]rune(NormQuery(strings.Repeat("ф", 500)))), 80)
	})
}

func TestKindOf(t *testing.T) {
	s := load(t)
	for qid, want := range map[string]string{
		"Q13417189": "movie", "Q79784": "tv-series", "Q246283": "cartoon", "Q25929253": "anime",
	} {
		assert.Equal(t, want, compact(t, s, qid).Kind, qid)
	}
	assert.Equal(t, "cartoon", KindOf([]string{"Q11424", "Q202866"}), "анимация сильнее")
	assert.Equal(t, "movie", KindOf([]string{"Q11424", "Q5398426"}))
	assert.Equal(t, "tv-series", KindOf([]string{"Q5398426", "Q11424"}))
	assert.Empty(t, KindOf([]string{"Q5"}))
}

func TestCompactEntity(t *testing.T) {
	s := load(t)
	c := compact(t, s, "Q13417189")
	assert.Equal(t, 258687, c.KP)
	assert.Equal(t, "tt0816692", c.IMDb)
	assert.Equal(t, 2014, c.Year)
	assert.Equal(t, "Q30", c.Country)
	assert.Contains(t, c.Genres, "scifi")
	assert.Contains(t, c.Genres, "adventure")
	assert.LessOrEqual(t, len(c.Genres), 3)
	assert.False(t, c.Adult)

	sr := compact(t, s, "Q79784")
	assert.Equal(t, [2]int{1994, 2004}, [2]int{sr.Start, sr.End})

	assert.True(t, compact(t, s, "Q50412717").Adult, "порно")
	assert.Zero(t, compact(t, s, "Q123515453").Year, "будущий фильм без даты")

	raw, err := json.Marshal(c)
	require.NoError(t, err)
	assert.Less(t, len(raw), 1500, "ради этого всё и затевалось")
}

func TestDocFromCompact(t *testing.T) {
	s := load(t)
	countries := map[string]map[string]string{"Q30": {"ru": "США", "en": "United States"}}
	doc := func(qid, lang string) Doc { return DocFromCompact(compact(t, s, qid), lang, countries) }

	ru, en := doc("Q13417189", "ru"), doc("Q13417189", "en")
	assert.Equal(t, "Интерстеллар", ru.Name)
	assert.Equal(t, "Interstellar", en.Name)
	assert.Equal(t, "Interstellar", ru.AlternativeName)
	assert.Empty(t, en.AlternativeName, "оригинал не повторяет название")
	assert.Equal(t, "Naruto", doc("Q25929253", "ru").AlternativeName, "латиница, а не иероглифы")

	assert.Equal(t, 258687, ru.ID)
	require.NotNil(t, ru.Poster)
	assert.Equal(t, "https://st.kp.yandex.net/images/film_iphone/iphone360_258687.jpg", ru.Poster.PreviewURL)
	assert.Equal(t, "https://www.kinopoisk.ru/film/258687/", ru.Link)

	noKP := doc("Q29957438", "ru")
	assert.Zero(t, noKP.ID)
	assert.Nil(t, noKP.Poster)
	assert.True(t, strings.HasPrefix(noKP.Link, "https://www.imdb.com/title/tt"))

	assert.Equal(t, 2014, ru.Year)
	end := 2004
	assert.Equal(t, []ReleaseYears{{Start: 1994, End: &end}}, doc("Q79784", "ru").ReleaseYears)

	var genres []string
	for _, g := range ru.Genres {
		genres = append(genres, g.Name)
	}
	assert.Contains(t, genres, "фантастика")
	assert.Equal(t, []Named{{Name: "США"}}, ru.Countries)
	assert.Contains(t, en.Genres, Named{Name: "sci-fi"})

	assert.Equal(t, "Friends", doc("Q79784", "de").Name, "общий ярлык mul")
	assert.Equal(t, "Друзья", doc("Q79784", "ru").Name)
	assert.Equal(t, "Interstellar", doc("Q13417189", "xx").Name, "незнакомый язык — английский")

	// Форма ответа совпадает с poiskkino: клиент читает тем же разбором.
	raw, err := json.Marshal(doc("Q79784", "ru"))
	require.NoError(t, err)
	assert.Contains(t, string(raw), `"releaseYears":[{"start":1994,"end":2004}]`)
}

func TestSearch(t *testing.T) {
	p := SearchParams("интерстеллар", false, 8)
	assert.Contains(t, p["srsearch"], "haswbstatement:P31=Q11424")
	assert.Contains(t, p["srsearch"], "P31=Q5398426")
	assert.True(t, strings.HasPrefix(p["srsearch"], "интерстеллар "))
	assert.True(t, strings.HasPrefix(SearchParams("гарри поттер и фило", true, 8)["srsearch"], "гарри поттер и фило* "))

	assert.True(t, Wildcard("гарри поттер и фило"))
	assert.False(t, Wildcard("оно"))

	assert.Equal(t, "Q13417189", SearchIDs(load(t).Search)[0])
	assert.Empty(t, SearchIDs(nil))
}

func TestQuote(t *testing.T) {
	assert.Equal(t, "Poster_%28film%29_%D0%A4.jpg", quote("Poster_(film)_Ф.jpg"))
}
