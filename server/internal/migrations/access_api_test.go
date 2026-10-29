package migrations_test

import (
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/migrations"
	"github.com/m0nstrum/togetherly/server/internal/migrations/schema"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

const (
	pairA = "pairaaaaaaaaaaa"
	pairB = "pairbbbbbbbbbbb"
)

// fixture — пара A (alice, bob) и посторонняя eve из пары B.
type fixture struct {
	app              *tests.TestApp
	alice, bob, eve  *core.Record
	aliceTok, eveTok string
	recordOfA        map[string]string // коллекция → id записи пары A
}

func newApp(t testing.TB) *tests.TestApp {
	t.Helper()
	app, err := tests.NewTestAppWithConfig(core.BaseAppConfig{DataDir: t.TempDir(), EncryptionEnv: "pb_test_env"})
	require.NoError(t, err)
	require.NoError(t, app.RunAllMigrations())
	return app
}

func user(t testing.TB, app core.App, id, email string, groups ...string) *core.Record {
	t.Helper()
	col, err := app.FindCollectionByNameOrId("users")
	require.NoError(t, err)
	u := core.NewRecord(col)
	u.Id = id
	u.SetEmail(email)
	u.SetPassword("password123")
	u.Set("group_ids", groups)
	u.Set("live_group_ids", groups)
	require.NoError(t, app.Save(u))
	return u
}

// groupField — поле, которым запись привязана к паре.
func groupField(col *core.Collection) string {
	switch {
	case col.Name == "live_sessions":
		return "id"
	case col.Fields.GetByName("group_id") != nil:
		return "group_id"
	case col.Fields.GetByName("pair_id") != nil:
		return "pair_id"
	}
	return ""
}

func newFixture(t testing.TB) *fixture {
	t.Helper()
	app := testutil.NewApp(t)
	f := &fixture{app: app, recordOfA: map[string]string{}}

	groups, err := app.FindCollectionByNameOrId("groups")
	require.NoError(t, err)
	for _, g := range []struct{ id, members string }{
		{pairA, `["aliceaaaaaaaaaa","bobbbbbbbbbbbbb"]`},
		{pairB, `["eveeeeeeeeeeeee"]`},
	} {
		r := core.NewRecord(groups)
		r.Id = g.id
		r.Set("members", g.members)
		require.NoError(t, app.Save(r))
	}
	f.alice = user(t, app, "aliceaaaaaaaaaa", "alice@example.org", pairA)
	f.bob = user(t, app, "bobbbbbbbbbbbbb", "bob@example.org", pairA)
	f.eve = user(t, app, "eveeeeeeeeeeeee", "eve@example.org", pairB)
	f.aliceTok, err = f.alice.NewAuthToken()
	require.NoError(t, err)
	f.eveTok, err = f.eve.NewAuthToken()
	require.NoError(t, err)

	// По записи пары A в каждой парной коллекции.
	cols, err := app.FindAllCollections(core.CollectionTypeBase)
	require.NoError(t, err)
	for _, col := range cols {
		gf := groupField(col)
		if gf == "" {
			continue
		}
		r := core.NewRecord(col)
		r.Id = core.GenerateDefaultRandomId()
		if gf == "id" {
			r.Id = pairA
		} else {
			r.Set(gf, pairA)
		}
		for _, af := range []string{"user_uid", "author_uid", "uid", "created_by", "owner_uid"} {
			if col.Fields.GetByName(af) != nil {
				r.Set(af, f.alice.Id)
			}
		}
		for _, fl := range col.Fields {
			if tf, ok := fl.(*core.TextField); ok && tf.Required && r.GetString(tf.Name) == "" && !tf.PrimaryKey {
				r.Set(tf.Name, "x")
			}
		}
		if col.Name == "cycle_entries" {
			r.Set("shared", true)
		}
		require.NoError(t, app.SaveNoValidate(r), col.Name)
		f.recordOfA[col.Name] = r.Id
	}
	require.NotEmpty(t, f.recordOfA)
	return f
}

func call(t testing.TB, app *tests.TestApp, method, url, token, body string) (int, string) {
	t.Helper()
	return testutil.Do(t, app, method, url, token, body)
}

// Посторонний не читает, не создаёт, не правит и не удаляет записи чужой
// пары ни в одной парной коллекции. Участник пары свою запись читает.
func TestStrangerCannotTouchPair(t *testing.T) {
	f := newFixture(t)
	defer f.app.Cleanup()

	for col, id := range f.recordOfA {
		t.Run(col, func(t *testing.T) {
			base := "/api/collections/" + col + "/records"

			code, body := call(t, f.app, http.MethodGet, base, f.eveTok, "")
			if code == http.StatusOK {
				assert.NotContains(t, body, id, "список выдал чужую запись")
			}

			code, _ = call(t, f.app, http.MethodGet, base+"/"+id, f.eveTok, "")
			assert.NotEqual(t, http.StatusOK, code, "чтение чужой записи")

			code, _ = call(t, f.app, http.MethodPatch, base+"/"+id, f.eveTok, `{}`)
			assert.NotEqual(t, http.StatusOK, code, "правка чужой записи")

			code, _ = call(t, f.app, http.MethodDelete, base+"/"+id, f.eveTok, "")
			assert.NotEqual(t, http.StatusNoContent, code, "удаление чужой записи")

			gf := "group_id"
			if col == "live_session_presence" || col == "live_session_chat" {
				gf = "pair_id"
			}
			body = `{"` + gf + `":"` + pairA + `","user_uid":"` + f.eve.Id + `","author_uid":"` + f.eve.Id + `","uid":"` + f.eve.Id + `"}`
			if col == "live_sessions" {
				body = `{"id":"` + pairA + `"}`
			}
			code, _ = call(t, f.app, http.MethodPost, base, f.eveTok, body)
			assert.NotEqual(t, http.StatusOK, code, "создание записи в чужой паре")

			// Участник свою запись видит (кроме тех, что только для сервера).
			if r := ruleOf(t, f.app, col); r != nil {
				code, _ = call(t, f.app, http.MethodGet, base+"/"+id, f.aliceTok, "")
				assert.Equal(t, http.StatusOK, code, "участник не видит свою запись")
			}
		})
	}

	t.Run("группа чужой пары", func(t *testing.T) {
		code, _ := call(t, f.app, http.MethodGet, "/api/collections/groups/records/"+pairA, f.eveTok, "")
		assert.NotEqual(t, http.StatusOK, code)
		code, _ = call(t, f.app, http.MethodGet, "/api/collections/groups/records/"+pairA, f.aliceTok, "")
		assert.Equal(t, http.StatusOK, code)
	})

	t.Run("свои медиа: аватар, файл пары; чужая пара — нет", func(t *testing.T) {
		post := func(tok, body string) int {
			code, _ := call(t, f.app, http.MethodPost, "/api/collections/media/records", tok, body)
			return code
		}
		assert.Equal(t, http.StatusOK, post(f.aliceTok, `{"uid":"`+f.alice.Id+`","group_id":"`+f.alice.Id+`","kind":"avatars"}`))
		assert.Equal(t, http.StatusOK, post(f.aliceTok, `{"uid":"`+f.alice.Id+`","group_id":"`+pairA+`","kind":"memories"}`))
		assert.Equal(t, http.StatusOK, post(f.aliceTok, `{"uid":"`+f.alice.Id+`","kind":"canvas"}`))
		assert.NotEqual(t, http.StatusOK, post(f.eveTok, `{"uid":"`+f.eve.Id+`","group_id":"`+pairA+`","kind":"memories"}`))
		assert.NotEqual(t, http.StatusOK, post(f.eveTok, `{"uid":"`+f.alice.Id+`","group_id":"`+f.alice.Id+`","kind":"avatars"}`))
	})

	t.Run("чужой профиль", func(t *testing.T) {
		code, _ := call(t, f.app, http.MethodGet, "/api/collections/users/records/"+f.alice.Id, f.eveTok, "")
		assert.NotEqual(t, http.StatusOK, code)
	})

	t.Run("аноним не видит ничего парного", func(t *testing.T) {
		for col := range f.recordOfA {
			code, body := call(t, f.app, http.MethodGet, "/api/collections/"+col+"/records", "", "")
			if code == http.StatusOK {
				assert.Contains(t, body, `"totalItems":0`, col)
			}
		}
	})
}

// Гипотеза AUDIT §2: по правилу апстрима посторонний может вбросить точку в
// канал геопозиции чужой пары. Подтверждается на правиле апстрима и
// закрывается правилом форка.
func TestLiveLocationInjection(t *testing.T) {
	inject := func(t *testing.T, f *fixture) int {
		body := `{"channel":"pair_` + f.alice.Id + `_` + f.bob.Id + `","user_uid":"` + f.eve.Id + `","data":{"lat":1,"lng":2}}`
		code, _ := call(t, f.app, http.MethodPost, "/api/collections/live_location/records", f.eveTok, body)
		return code
	}

	t.Run("правило апстрима пропускает", func(t *testing.T) {
		f := newFixture(t)
		defer f.app.Cleanup()
		col, err := f.app.FindCollectionByNameOrId("live_location")
		require.NoError(t, err)
		upstream := `@request.auth.id != "" && user_uid = @request.auth.id`
		col.CreateRule = &upstream
		require.NoError(t, f.app.Save(col))
		assert.Equal(t, http.StatusOK, inject(t, f), "гипотеза AUDIT не подтвердилась")
	})

	t.Run("правило форка не пускает", func(t *testing.T) {
		f := newFixture(t)
		defer f.app.Cleanup()
		assert.NotEqual(t, http.StatusOK, inject(t, f))
	})
}

// D11: точку партнёра отдают только тому, кто делится сам, то есть держит
// свою запись в том же канале. Своя точка видна всегда.
func TestLiveLocationMutual(t *testing.T) {
	f := newFixture(t)
	defer f.app.Cleanup()
	bobTok, err := f.bob.NewAuthToken()
	require.NoError(t, err)
	channel := "pair_" + f.alice.Id + "_" + f.bob.Id
	base := "/api/collections/live_location/records"

	col, err := f.app.FindCollectionByNameOrId("live_location")
	require.NoError(t, err)
	put := func(ch, uid string) *core.Record {
		r := core.NewRecord(col)
		r.Set("channel", ch)
		r.Set("user_uid", uid)
		r.Set("data", map[string]any{"c": "sealed"})
		require.NoError(t, f.app.Save(r))
		return r
	}
	bobPoint := put(channel, f.bob.Id)

	sees := func(tok string) bool {
		code, body := call(t, f.app, http.MethodGet, base+"?perPage=50", tok, "")
		require.Equal(t, http.StatusOK, code, body)
		inList := strings.Contains(body, bobPoint.Id)
		code, _ = call(t, f.app, http.MethodGet, base+"/"+bobPoint.Id, tok, "")
		assert.Equal(t, inList, code == http.StatusOK, "список и чтение расходятся")
		return inList
	}

	t.Run("не делится — не видит", func(t *testing.T) {
		assert.False(t, sees(f.aliceTok))
	})

	t.Run("запись в другом канале не открывает этот", func(t *testing.T) {
		other := put(pairA, f.alice.Id)
		defer func() { require.NoError(t, f.app.Delete(other)) }()
		assert.False(t, sees(f.aliceTok))
	})

	var mine string
	t.Run("включила показ — видит", func(t *testing.T) {
		code, body := call(t, f.app, http.MethodPost, base, f.aliceTok,
			`{"channel":"`+channel+`","user_uid":"`+f.alice.Id+`"}`)
		require.Equal(t, http.StatusOK, code, body)
		mine = recordID(t, body)
		assert.True(t, sees(f.aliceTok))
	})

	t.Run("выключила — снова не видит", func(t *testing.T) {
		code, _ := call(t, f.app, http.MethodDelete, base+"/"+mine, f.aliceTok, "")
		require.Equal(t, http.StatusNoContent, code)
		assert.False(t, sees(f.aliceTok))
	})

	t.Run("свою точку видно и без чужой", func(t *testing.T) {
		assert.True(t, sees(bobTok))
	})

	t.Run("посторонний со своей записью в канале не видит", func(t *testing.T) {
		put(channel, f.eve.Id)
		assert.False(t, sees(f.eveTok))
	})
}

func recordID(t testing.TB, body string) string {
	t.Helper()
	var rec struct {
		ID string `json:"id"`
	}
	require.NoError(t, json.Unmarshal([]byte(body), &rec))
	require.NotEmpty(t, rec.ID)
	return rec.ID
}

// У каждой коллекции схемы есть правила, выкинутых коллекций нет.
func TestMigrationShape(t *testing.T) {
	app := newApp(t)
	defer app.Cleanup()

	require.NoError(t, migrations.ApplyRules(app))
	for name := range migrations.Dropped {
		_, err := app.FindCollectionByNameOrId(name)
		assert.Error(t, err, "выкинутая коллекция %s создана", name)
	}
	for _, name := range []string{"custom_moods", "love_tests", "miss_you_events"} {
		_, err := app.FindCollectionByNameOrId(name)
		assert.NoError(t, err, name)
	}
	users, err := app.FindCollectionByNameOrId("users")
	require.NoError(t, err)
	gids, ok := users.Fields.GetByName("group_ids").(*core.RelationField)
	require.True(t, ok)
	assert.True(t, gids.Hidden, "group_ids не должен уходить клиенту")
	live, ok := users.Fields.GetByName("live_group_ids").(*core.RelationField)
	require.True(t, ok)
	assert.True(t, live.Hidden, "live_group_ids не должен уходить клиенту")
}

// Копия схемы в модуле совпадает с pocketbase/collections_schema.json.
// Упало — выполните `go generate ./...` в server/.
func TestSchemaCopyInSync(t *testing.T) {
	orig, err := os.ReadFile("../../../pocketbase/collections_schema.json")
	require.NoError(t, err)
	assert.Equal(t, strings.TrimSpace(string(orig)), strings.TrimSpace(string(schema.UpstreamJSON)))
}

func ruleOf(t testing.TB, app core.App, name string) *string {
	t.Helper()
	col, err := app.FindCollectionByNameOrId(name)
	require.NoError(t, err)
	return col.ViewRule
}

// Шифрованные поля чата вмещают шифртекст длинного сообщения.
func TestSealedFieldsFitCiphertext(t *testing.T) {
	app := newApp(t)
	defer app.Cleanup()

	col, err := app.FindCollectionByNameOrId("chat_messages")
	require.NoError(t, err)
	for _, f := range []string{"user_name", "text", "pin_title", "reply_to_name", "reply_to_text"} {
		tf, ok := col.Fields.GetByName(f).(*core.TextField)
		require.True(t, ok, f)
		assert.Equal(t, migrations.E2ESealedMax, tf.Max, f)
	}
	for col, fields := range map[string][]string{
		"wishes": {"title", "url"}, "custom_moods": {"label", "emoji"},
		"widget_data": {"status", "message"}, "miss_you": {"last_vibe_text"},
		"chat_messages": {"voice_url", "voice_peaks", "face"}, "memories": {"author_name"},
		"canvas_meta": {"coloring_outline"}, "mascots": {"name"}, "groups": {"chat_background"},
	} {
		c, err := app.FindCollectionByNameOrId(col)
		require.NoError(t, err, col)
		for _, f := range fields {
			tf, ok := c.Fields.GetByName(f).(*core.TextField)
			require.True(t, ok, col+"."+f)
			assert.Equal(t, migrations.E2ESealedMax, tf.Max, col+"."+f)
		}
	}
	comments, err := app.FindCollectionByNameOrId("memory_comments")
	require.NoError(t, err)
	tf, ok := comments.Fields.GetByName("text").(*core.TextField)
	require.True(t, ok)
	assert.Equal(t, migrations.E2ESealedMax, tf.Max)
}

// У цикла есть поле `enc`, куда клиент переносит дату отметки.
func TestMovedFieldsHaveEnc(t *testing.T) {
	app := newApp(t)
	defer app.Cleanup()

	for _, name := range []string{"cycle_entries", "groups", "chat_messages", "wishes", "canvas_meta"} {
		col, err := app.FindCollectionByNameOrId(name)
		require.NoError(t, err)
		tf, ok := col.Fields.GetByName("enc").(*core.TextField)
		require.True(t, ok, name)
		assert.Equal(t, migrations.E2ESealedMax, tf.Max, name)
	}
}

// A breakup retains the archive but revokes writes and current profile access.
// Keep the pre-breakup auth token: authorization must follow the database.
func TestFormerPartnerAccess(t *testing.T) {
	f := newFixture(t)
	defer f.app.Cleanup()
	for _, name := range []string{"user_presence", "e2e_identities", "media"} {
		col, err := f.app.FindCollectionByNameOrId(name)
		require.NoError(t, err)
		r := core.NewRecord(col)
		r.Set("user_uid", f.bob.Id)
		r.Set("uid", f.bob.Id)
		r.Set("group_id", f.bob.Id)
		if name == "e2e_identities" {
			r.Set("account_key", "public-key")
		}
		require.NoError(t, f.app.Save(r))
		code, _ := call(t, f.app, "GET", "/api/collections/"+name+"/records/"+r.Id, f.aliceTok, "")
		require.Equal(t, 200, code, name)
	}
	g, err := f.app.FindRecordById("groups", pairA)
	require.NoError(t, err)
	g.Set("disbanded", true)
	require.NoError(t, f.app.Save(g))
	// API-rule fixture has no JS hooks; the live-server test covers their resync.
	f.alice.Set("live_group_ids", []string{})
	require.NoError(t, f.app.Save(f.alice))
	for _, name := range []string{"user_presence", "e2e_identities", "media"} {
		code, body := call(t, f.app, "GET", "/api/collections/"+name+"/records", f.aliceTok, "")
		require.Equal(t, 200, code)
		assert.NotContains(t, body, f.bob.Id, name)
	}
	for name, id := range f.recordOfA {
		if name == "invite_codes" {
			continue
		}
		base := "/api/collections/" + name + "/records/" + id
		code, _ := call(t, f.app, "PATCH", base, f.aliceTok, `{}`)
		assert.NotEqual(t, 200, code, "former partner updated %s", name)
		code, _ = call(t, f.app, "DELETE", base, f.aliceTok, "")
		assert.NotEqual(t, 204, code, "former partner deleted %s", name)
	}
	code, _ := call(t, f.app, "GET", "/api/collections/chat_messages/records/"+f.recordOfA["chat_messages"], f.aliceTok, "")
	assert.Equal(t, 200, code, "archive remains readable")
}
