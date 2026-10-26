package handler_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pairs"
)

// Пара в ожидании целиком: завести, поправить заглушку, заявка, отказ,
// повторная заявка, подтверждение; статус для ждущего на каждом шаге.
func TestWaitingFlow(t *testing.T) {
	app := testutil.NewApp(t)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.Waiting(e.Router, pairs.New(app), time.Now, slog.New(slog.NewTextHandler(io.Discard, nil)))
		return e.Next()
	})
	_, her := testutil.User(t, app, "waither00000001")
	_, him := testutil.User(t, app, "waithim00000001")
	_, eve := testutil.User(t, app, "waiteve00000001")
	call := func(method, path, tok, body string) (int, map[string]any) {
		code, raw := testutil.Do(t, app, method, "/api/waiting/"+path, tok, body)
		out := map[string]any{}
		_ = json.Unmarshal([]byte(raw), &out)
		return code, out
	}

	code, res := call(http.MethodPost, "create", her, `{"name":"Артём","returnDate":"2027-05-01"}`)
	require.Equal(t, http.StatusOK, code, res)
	gid, _ := res["pairId"].(string)
	require.NotEmpty(t, gid, res)
	g, err := app.FindRecordById("groups", gid)
	require.NoError(t, err)
	token := g.GetString("claim_token")
	require.NotEmpty(t, token)

	code, _ = call(http.MethodPost, "update", her, `{"groupId":"`+gid+`","name":"Тёма"}`)
	require.Equal(t, http.StatusOK, code)
	code, _ = call(http.MethodPost, "update", eve, `{"groupId":"`+gid+`","name":"x"}`)
	assert.Equal(t, http.StatusForbidden, code)

	_, res = call(http.MethodGet, "state?code="+token, him, "")
	assert.Equal(t, "rejected", res["status"], "заявки ещё нет")
	code, res = call(http.MethodPost, "claim", him, `{"code":"`+token+`"}`)
	require.Equal(t, http.StatusOK, code, res)
	assert.Equal(t, "pending", res["status"])
	_, res = call(http.MethodGet, "state?code="+token, him, "")
	assert.Equal(t, "pending", res["status"])

	code, res = call(http.MethodPost, "approve", her, `{"groupId":"`+gid+`","approve":false}`)
	require.Equal(t, http.StatusOK, code, res)
	assert.Equal(t, false, res["approved"])
	_, res = call(http.MethodGet, "state?code="+token, him, "")
	assert.Equal(t, "rejected", res["status"])

	call(http.MethodPost, "claim", him, `{"code":"`+token+`"}`)
	code, res = call(http.MethodPost, "approve", him, `{"groupId":"`+gid+`"}`)
	assert.Equal(t, http.StatusForbidden, code, "подтверждает только хозяйка")
	code, res = call(http.MethodPost, "approve", her, `{"groupId":"`+gid+`"}`)
	require.Equal(t, http.StatusOK, code, res)
	assert.Equal(t, true, res["approved"])
	g, err = app.FindRecordById("groups", gid)
	require.NoError(t, err)
	assert.ElementsMatch(t, []string{"waither00000001", "waithim00000001"}, pairs.Members(g))
	assert.Empty(t, g.GetString("claim_token"), "код погашен")
	_, res = call(http.MethodGet, "state?code="+token, him, "")
	assert.Equal(t, "approved", res["status"])

	code, _ = call(http.MethodPost, "cancel", her, `{"groupId":"`+gid+`"}`)
	assert.Equal(t, http.StatusBadRequest, code, "занятое место — обычная пара")
	code, _ = call(http.MethodPost, "claim", eve, `{"code":"NOPE"}`)
	assert.Equal(t, http.StatusNotFound, code)
}

// Отмена ожидания распускает пару и гасит код.
func TestWaitingCancel(t *testing.T) {
	app := testutil.NewApp(t)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.Waiting(e.Router, pairs.New(app), time.Now, slog.New(slog.NewTextHandler(io.Discard, nil)))
		return e.Next()
	})
	_, her := testutil.User(t, app, "waitcan00000001")
	code, raw := testutil.Do(t, app, http.MethodPost, "/api/waiting/create", her, `{"name":"Артём"}`)
	require.Equal(t, http.StatusOK, code, raw)
	var res struct{ PairID string }
	require.NoError(t, json.Unmarshal([]byte(raw), &res))
	code, raw = testutil.Do(t, app, http.MethodPost, "/api/waiting/cancel", her, `{"groupId":"`+res.PairID+`"}`)
	require.Equal(t, http.StatusOK, code, raw)
	g, err := app.FindRecordById("groups", res.PairID)
	require.NoError(t, err)
	assert.True(t, g.GetBool("disbanded"))
	assert.Empty(t, g.GetString("claim_token"))
	code, raw = testutil.Do(t, app, http.MethodPost, "/api/waiting/cancel", her, `{"groupId":"`+res.PairID+`"}`)
	assert.Contains(t, raw, `"already":true`)
}
