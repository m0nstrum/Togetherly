package handler_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

func TestNormalizeInviteCode(t *testing.T) {
	for in, want := range map[string]string{
		" hq792s ":                          "HQ792S",
		"https://x.app/invite/hq792s?utm=1": "HQ792S",
		"АВС123":                            "ABC123",
		"«HQ-792S»":                         "HQ792S",
		"":                                  "",
	} {
		assert.Equal(t, want, handler.NormalizeInviteCode(in), in)
	}
}

// Приём кода: пара складывается, повтор — тот же успех, свой код и чужой
// третий — отказ; код ожидания отдаёт заявку.
func TestInviteAccept(t *testing.T) {
	app := testutil.NewApp(t)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.InviteAccept(e.Router, pairs.New(app), slog.New(slog.NewTextHandler(io.Discard, nil)))
		return e.Next()
	})
	_, owner := testutil.User(t, app, "invowner0000001")
	_, guest := testutil.User(t, app, "invguest0000001")
	_, third := testutil.User(t, app, "invthird0000001")
	col, err := app.FindCollectionByNameOrId("invite_codes")
	require.NoError(t, err)
	c := core.NewRecord(col)
	c.Set("code", "HQ792S")
	c.Set("owner_uid", "invowner0000001")
	require.NoError(t, app.Save(c))

	accept := func(tok, code string) (int, map[string]any) {
		status, body := testutil.Do(t, app, http.MethodPost, "/api/invite/accept", tok, `{"code":"`+code+`"}`)
		out := map[string]any{}
		_ = json.Unmarshal([]byte(body), &out)
		return status, out
	}
	status, res := accept(owner, "HQ792S")
	assert.Equal(t, http.StatusBadRequest, status, "свой код")
	status, res = accept(guest, "nope")
	assert.Equal(t, http.StatusNotFound, status)

	status, res = accept(guest, "https://x/invite/hq792s")
	require.Equal(t, http.StatusOK, status, res)
	pair, _ := res["pairId"].(string)
	require.NotEmpty(t, pair)
	g, err := app.FindRecordById("groups", pair)
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"invowner0000001", "invguest0000001"}, pairs.Members(g))
	c, err = app.FindRecordById("invite_codes", c.Id)
	require.NoError(t, err)
	assert.Equal(t, pair, c.GetString("group_id"), "код привязан к паре")

	status, res = accept(guest, "HQ792S")
	assert.Equal(t, http.StatusOK, status, "повтор — тот же успех")
	assert.Equal(t, pair, res["pairId"])
	status, _ = accept(third, "HQ792S")
	assert.NotEqual(t, http.StatusOK, status, "третьему места нет")

	// Код второго места пары в ожидании.
	w := testutil.Group(t, app, "invwaitaaaaaaaa", "invthird0000001")
	w.Set("claim_token", "WAIT42")
	require.NoError(t, app.Save(w))
	status, res = accept(guest, "wait42")
	assert.Equal(t, http.StatusOK, status)
	assert.Equal(t, true, res["waiting"])
	assert.Equal(t, "invwaitaaaaaaaa", res["pairId"])
}
