package migrations_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Комментарий к воспоминанию сохраняет пояс автора: без него приложение
// читает UTC-время как часы автора и показывает его по Гринвичу.
func TestMemoryCommentKeepsAuthorZone(t *testing.T) {
	f := newFixture(t)
	defer f.app.Cleanup()
	base := "/api/collections/memory_comments/records"
	code, response := call(t, f.app, http.MethodPost, base, f.aliceTok,
		`{"group_id":"`+pairA+`","memory_id":"m1","author_uid":"`+f.alice.Id+`",`+
			`"text":"opaque","created_at":"2026-10-29 07:00:00.000Z","tz":"+03:00"}`)
	require.Equal(t, http.StatusOK, code, response)
	var record struct {
		ID string `json:"id"`
		TZ string `json:"tz"`
	}
	require.NoError(t, json.Unmarshal([]byte(response), &record))
	assert.Equal(t, "+03:00", record.TZ)

	code, response = call(t, f.app, http.MethodGet, base+"/"+record.ID, f.aliceTok, "")
	require.Equal(t, http.StatusOK, code, response)
	require.NoError(t, json.Unmarshal([]byte(response), &record))
	assert.Equal(t, "+03:00", record.TZ)
}

// Во все коллекции, куда приложение пишет `tz`, поле есть в схеме.
func TestPairTimeZoneFields(t *testing.T) {
	app := newApp(t)
	defer app.Cleanup()
	for _, name := range []string{"memories", "memory_comments", "mood_entries"} {
		col, err := app.FindCollectionByNameOrId(name)
		require.NoError(t, err)
		assert.NotNil(t, col.Fields.GetByName("tz"), name)
	}
}
