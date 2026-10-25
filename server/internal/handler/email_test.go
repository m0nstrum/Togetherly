package handler_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"regexp"
	"testing"
	"time"

	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

// Вход и «Забыли пароль» находят аккаунт, набранный с другой заглавной;
// двойников по регистру не трогают.
func TestEmailCase(t *testing.T) {
	app := testutil.NewApp(t)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	now := time.Now()
	clock := func() time.Time { return now }
	handler.EmailCaseLogin(app)
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.PasswordReset(e.Router, clock, log)
		return e.Next()
	})
	testutil.User(t, app, "caseanna0000001")
	for _, id := range []string{"casetwin0000001", "casetwin0000002"} {
		u, _ := testutil.User(t, app, id)
		u.SetEmail(map[string]string{"casetwin0000001": "twin@example.org", "casetwin0000002": "Twin@example.org"}[id])
		require.NoError(t, app.Save(u))
	}
	login := func(email string) int {
		code, _ := testutil.Do(t, app, http.MethodPost, "/api/collections/users/auth-with-password", "",
			`{"identity":"`+email+`","password":"password123"}`)
		return code
	}
	assert.Equal(t, http.StatusOK, login("CaseAnna0000001@Example.org"))
	assert.Equal(t, http.StatusOK, login("twin@example.org"), "точное совпадение")
	assert.NotEqual(t, http.StatusOK, login("TWIN@example.org"), "двойники по регистру")

	reset := func(email string) int {
		code, _ := testutil.Do(t, app, http.MethodPost, "/api/auth/password-reset", "", `{"email":"`+email+`"}`)
		return code
	}
	assert.Equal(t, http.StatusNoContent, reset("CASEANNA0000001@example.org"))
	assert.Equal(t, 1, app.TestMailer.TotalSend())
	assert.Equal(t, http.StatusNoContent, reset("caseanna0000001@example.org"))
	assert.Equal(t, 1, app.TestMailer.TotalSend(), "повтор не раньше двух минут")
	now = now.Add(3 * time.Minute)
	assert.Equal(t, http.StatusNoContent, reset("caseanna0000001@example.org"))
	assert.Equal(t, 2, app.TestMailer.TotalSend())
	assert.Equal(t, http.StatusNoContent, reset("nobody@example.org"), "по ответу не узнать")
	assert.Equal(t, http.StatusBadRequest, reset("nope"))
}

// Смена почты: код на новый адрес, пять попыток, занятый адрес не берётся,
// после смены — новый токен.
func TestEmailChange(t *testing.T) {
	app := testutil.NewApp(t)
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	now := time.Now()
	clock := func() time.Time { return now }
	app.OnServe().BindFunc(func(e *core.ServeEvent) error {
		handler.EmailChange(e.Router, clock, log)
		return e.Next()
	})
	_, tok := testutil.User(t, app, "chgalice0000001")
	testutil.User(t, app, "chgbob000000001")
	post := func(path, body string) (int, string) {
		return testutil.Do(t, app, http.MethodPost, "/api/account/email-change/"+path, tok, body)
	}

	code, body := post("request", `{"email":"bad"}`)
	assert.Equal(t, http.StatusBadRequest, code, body)
	code, body = post("request", `{"email":"ChgAlice0000001@example.org"}`)
	assert.Contains(t, body, `"same"`)
	code, body = post("request", `{"email":"chgbob000000001@example.org"}`)
	assert.Equal(t, http.StatusConflict, code, body)

	code, body = post("request", `{"email":"New@Example.org","lang":"en"}`)
	require.Equal(t, http.StatusOK, code, body)
	msg := app.TestMailer.LastMessage()
	assert.Equal(t, "new@example.org", msg.To[0].Address)
	pin := regexp.MustCompile(`>(\d{6})<`).FindStringSubmatch(msg.HTML)[1]
	code, body = post("request", `{"email":"new@example.org"}`)
	assert.Contains(t, body, `"wait"`, "не чаще раза в минуту")

	code, body = post("confirm", `{"email":"other@example.org","code":"`+pin+`"}`)
	assert.Contains(t, body, `"expired"`, "код к другому адресу")
	wrong := "000000"
	if pin == wrong {
		wrong = "111111"
	}
	code, body = post("confirm", `{"email":"new@example.org","code":"`+wrong+`"}`)
	assert.Contains(t, body, `"wrong"`)

	code, body = post("confirm", `{"email":"new@example.org","code":"`+pin[:3]+" "+pin[3:]+`"}`)
	require.Equal(t, http.StatusOK, code, body)
	var res struct{ Token string }
	require.NoError(t, json.Unmarshal([]byte(body), &res))
	assert.NotEmpty(t, res.Token)
	u, err := app.FindRecordById("users", "chgalice0000001")
	require.NoError(t, err)
	assert.Equal(t, "new@example.org", u.Email())
	assert.True(t, u.Verified())
	code, body = post("confirm", `{"email":"new@example.org","code":"`+pin+`"}`)
	assert.NotEqual(t, http.StatusOK, code, "код одноразовый")

	// Пять неверных — и даже верный код уже не примут.
	_, tok = testutil.User(t, app, "chgcarol0000001")
	now = now.Add(2 * time.Minute)
	code, body = post("request", `{"email":"carol@example.org"}`)
	require.Equal(t, http.StatusOK, code, body)
	pin = regexp.MustCompile(`>(\d{6})<`).FindStringSubmatch(app.TestMailer.LastMessage().HTML)[1]
	wrong = "000000"
	if pin == wrong {
		wrong = "111111"
	}
	for range 5 {
		post("confirm", `{"email":"carol@example.org","code":"`+wrong+`"}`)
	}
	code, body = post("confirm", `{"email":"carol@example.org","code":"`+pin+`"}`)
	assert.Contains(t, body, `"tries"`)
}
