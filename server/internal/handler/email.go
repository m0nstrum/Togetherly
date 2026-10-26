package handler

import (
	"fmt"
	"html"
	"log/slog"
	"math"
	"net/http"
	"net/mail"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/apis"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/mails"
	"github.com/pocketbase/pocketbase/tools/mailer"
	"github.com/pocketbase/pocketbase/tools/router"
	"github.com/pocketbase/pocketbase/tools/security"
)

// Почта без учёта регистра (бывший email_case.pb.js).
//
// PocketBase ищет почту без учёта регистра, только если у уникального
// индекса по `email` стоит `COLLATE NOCASE`. У нас индекс старый, без него:
// клавиатура телефона ставит первой букве заглавную, и «Anna@gmail.com» не
// находил аккаунт «anna@gmail.com» — вход отвечал «неверный пароль», а
// «Забыли пароль» молча не слал письмо. Пересоздать индекс нельзя: в базе
// есть пары аккаунтов, различающихся только регистром. Поэтому штатный поиск
// идёт первым, а без учёта регистра ищем только при промахе и берём аккаунт,
// лишь когда такой адрес в базе один.

// FindUserByEmailFold — единственный аккаунт с адресом email без учёта
// регистра; nil, если таких нет или их несколько.
func FindUserByEmailFold(app core.App, email string) *core.Record {
	var rows []struct {
		ID string `db:"id"`
	}
	err := app.DB().NewQuery("SELECT id FROM users WHERE lower(email) = lower({:e}) LIMIT 2").
		Bind(dbx.Params{"e": email}).All(&rows)
	if err != nil || len(rows) != 1 {
		return nil
	}
	rec, err := app.FindRecordById("users", rows[0].ID)
	if err != nil {
		return nil
	}
	return rec
}

// EmailCaseLogin — вход паролем без учёта регистра. Ненайденный аккаунт
// PocketBase передаёт хуку пустым и пароль проверяет сам после хука.
func EmailCaseLogin(app core.App) {
	app.OnRecordAuthWithPasswordRequest("users").BindFunc(func(e *core.RecordAuthWithPasswordRequestEvent) error {
		byEmail := e.IdentityField == "" || e.IdentityField == "email"
		if e.Record == nil && byEmail && strings.Index(e.Identity, "@") > 0 {
			e.Record = FindUserByEmailFold(e.App, strings.TrimSpace(e.Identity))
		}
		return e.Next()
	})
}

// PasswordReset — POST /api/auth/password-reset {email}: «Забыли пароль» без
// учёта регистра. Штатный маршрут ищет аккаунт до любого хука, поэтому свой.
//
// Ответ всегда 204, как у PocketBase: по нему не узнать, есть ли адрес.
// Повтор одному аккаунту — не чаще раза в две минуты; с адреса — не больше 30
// запросов в час: письма стоят квоты почтового сервиса.
func PasswordReset(r *router.Router[*core.RequestEvent], now func() time.Time, log *slog.Logger) {
	ips := &IPLimiter{Max: 30, Window: time.Hour}
	var mu sync.Mutex
	last := map[string]time.Time{}
	r.POST("/api/auth/password-reset", func(e *core.RequestEvent) error {
		at := now()
		if !ips.Allow(e.RealIP(), at) {
			return e.JSON(http.StatusTooManyRequests, map[string]any{"message": "Слишком много запросов. Попробуйте через час."})
		}
		var body struct {
			Email string `json:"email"`
		}
		_ = e.BindBody(&body)
		email := strings.TrimSpace(body.Email)
		if strings.Index(email, "@") < 1 || len(email) > 255 {
			return e.JSON(http.StatusBadRequest, map[string]any{"message": "Нужна почта."})
		}
		rec, err := e.App.FindAuthRecordByEmail("users", email)
		if err != nil {
			rec = FindUserByEmailFold(e.App, email)
		}
		if rec == nil {
			log.Info("pwreset: адреса нет")
			return e.NoContent(http.StatusNoContent)
		}
		mu.Lock()
		if t, ok := last[rec.Id]; ok && at.Sub(t) < 2*time.Minute {
			mu.Unlock()
			return e.NoContent(http.StatusNoContent)
		}
		for id, t := range last {
			if at.Sub(t) >= 2*time.Minute {
				delete(last, id)
			}
		}
		last[rec.Id] = at
		mu.Unlock()
		if err := mails.SendRecordPasswordReset(e.App, rec); err != nil {
			// Письмо не ушло — снимаем отметку, чтобы можно было нажать ещё раз.
			mu.Lock()
			delete(last, rec.Id)
			mu.Unlock()
			log.Error("pwreset: письмо не ушло", "uid", rec.Id, "err", err)
		}
		return e.NoContent(http.StatusNoContent)
	})
}

// Смена почты кодом из письма (бывший email_change.pb.js).
//
// Штатная смена PocketBase не годится: письмо английское, ссылка ведёт в
// админку, а подтверждение просит пароль. Поэтому свой путь:
//
//	POST /api/account/email-change/request {email, lang} → код на НОВЫЙ адрес;
//	POST /api/account/email-change/confirm {email, code} → почта сменена и
//	     подтверждена, в ответе новый токен (старые смена обнуляет).
//
// Код живёт 15 минут в памяти процесса; попыток ввода пять; писем — не чаще
// раза в минуту и не больше пяти в час. Ошибки несут `code`: invalid, same,
// taken, wait, limit, expired, wrong, tries, mail.

var emailShape = regexp.MustCompile(`^[^\s@]+@[^\s@]+\.[^\s@]{2,}$`)

type emailChange struct {
	email, code string
	exp         time.Time
	tries       int
	sends       []time.Time
}

// EmailChange — оба маршрута смены почты.
func EmailChange(r *router.Router[*core.RequestEvent], now func() time.Time, log *slog.Logger) {
	var mu sync.Mutex
	pending := map[string]*emailChange{}
	fail := func(e *core.RequestEvent, status int, code string) error {
		return e.JSON(status, map[string]any{"code": code})
	}
	taken := func(app core.App, email, except string) bool {
		var n int
		_ = app.DB().NewQuery("SELECT COUNT(*) FROM users WHERE lower(email) = {:e} AND id != {:id}").
			Bind(dbx.Params{"e": email, "id": except}).Row(&n)
		return n > 0
	}

	r.POST("/api/account/email-change/request", func(e *core.RequestEvent) error {
		var body struct{ Email, Lang string }
		_ = e.BindBody(&body)
		email := strings.ToLower(strings.TrimSpace(body.Email))
		if !emailShape.MatchString(email) || len(email) > 200 {
			return fail(e, http.StatusBadRequest, "invalid")
		}
		if email == strings.ToLower(e.Auth.Email()) {
			return fail(e, http.StatusBadRequest, "same")
		}
		if taken(e.App, email, "") {
			return fail(e, http.StatusConflict, "taken")
		}

		at := now()
		mu.Lock()
		p := pending[e.Auth.Id]
		if p == nil {
			p = &emailChange{}
			pending[e.Auth.Id] = p
		}
		sends := p.sends[:0:0]
		for _, t := range p.sends {
			if at.Sub(t) < time.Hour {
				sends = append(sends, t)
			}
		}
		p.sends = sends
		if n := len(sends); n > 0 && at.Sub(sends[n-1]) < time.Minute {
			left := time.Minute - at.Sub(sends[n-1])
			mu.Unlock()
			return e.JSON(http.StatusTooManyRequests, map[string]any{"code": "wait", "retryIn": int(math.Ceil(left.Seconds()))})
		}
		if len(sends) >= 5 {
			mu.Unlock()
			return fail(e, http.StatusTooManyRequests, "limit")
		}
		// Отметку ставим до отправки: иначе пачка параллельных запросов
		// проходила проверку «раз в минуту», пока письмо ещё шло.
		p.sends = append(p.sends, at)
		mu.Unlock()
		unsend := func() {
			mu.Lock()
			if i := slices.Index(p.sends, at); i >= 0 {
				p.sends = slices.Delete(p.sends, i, i+1)
			}
			mu.Unlock()
		}

		code := security.RandomStringWithAlphabet(6, "0123456789")
		meta := e.App.Settings().Meta
		subject, htmlBody := emailChangeLetter(meta.AppName, body.Lang, code)
		msg := &mailer.Message{
			From:    mail.Address{Address: meta.SenderAddress, Name: meta.SenderName},
			To:      []mail.Address{{Address: email}},
			Subject: subject,
			HTML:    htmlBody,
		}
		if err := e.App.NewMailClient().Send(msg); err != nil {
			unsend()
			log.Warn("email-change: письмо не ушло", "uid", e.Auth.Id, "err", err)
			return fail(e, http.StatusBadGateway, "mail")
		}
		mu.Lock()
		p.email, p.code, p.exp, p.tries = email, code, at.Add(15*time.Minute), 0
		mu.Unlock()
		log.Info("email-change: код отправлен", "uid", e.Auth.Id)
		return e.JSON(http.StatusOK, map[string]any{"ok": true, "retryIn": 60})
	}).Bind(apis.RequireAuth("users"))

	r.POST("/api/account/email-change/confirm", func(e *core.RequestEvent) error {
		var body struct{ Email, Code string }
		_ = e.BindBody(&body)
		email := strings.ToLower(strings.TrimSpace(body.Email))
		code := strings.Map(func(r rune) rune {
			if r >= '0' && r <= '9' {
				return r
			}
			return -1
		}, body.Code)

		mu.Lock()
		p := pending[e.Auth.Id]
		if p == nil || p.code == "" || p.email != email || now().After(p.exp) {
			mu.Unlock()
			return fail(e, http.StatusBadRequest, "expired")
		}
		if p.tries >= 5 {
			mu.Unlock()
			return fail(e, http.StatusTooManyRequests, "tries")
		}
		if !security.Equal(code, p.code) {
			p.tries++
			tries := p.tries
			mu.Unlock()
			if tries >= 5 {
				return fail(e, http.StatusBadRequest, "tries")
			}
			return fail(e, http.StatusBadRequest, "wrong")
		}
		// Код одноразовый; письма этого часа остаются в лимите.
		p.code, p.email = "", ""
		mu.Unlock()

		// Адрес мог занять кто-то другой, пока письмо шло.
		if taken(e.App, email, e.Auth.Id) {
			return fail(e, http.StatusConflict, "taken")
		}
		rec, err := e.App.FindRecordById("users", e.Auth.Id)
		if err != nil {
			return e.NotFoundError("", err)
		}
		old := rec.Email()
		rec.SetEmail(email)
		rec.SetVerified(true)
		if err := e.App.Save(rec); err != nil {
			return e.InternalServerError("", err)
		}
		log.Info("email-change: почта сменена", "uid", rec.Id, "from", old, "to", email)
		token, err := rec.NewAuthToken()
		if err != nil {
			return e.InternalServerError("", err)
		}
		return e.JSON(http.StatusOK, map[string]any{"ok": true, "email": email, "token": token})
	}).Bind(apis.RequireAuth("users"))
}

// emailChangeLetter — тема и тело письма с кодом на языке приложения.
func emailChangeLetter(app, lang, code string) (string, string) {
	var subject, intro, outro string
	switch lang {
	case "ru", "":
		subject = "Код для смены почты в " + app
		intro = "Вы меняете почту аккаунта " + app + " на этот адрес. Введите код в приложении:"
		outro = "Код действует 15 минут. Если вы ничего не меняли, просто удалите это письмо."
	case "zh":
		subject = app + " 更换邮箱验证码"
		intro = "你正在把 " + app + " 账号的邮箱改为这个地址。请在应用里输入验证码："
		outro = "验证码 15 分钟内有效。如果不是你本人操作，删除这封邮件即可。"
	default:
		subject = "Your " + app + " email change code"
		intro = "You are changing your " + app + " account email to this address. Enter the code in the app:"
		outro = "The code is valid for 15 minutes. If this wasn't you, just delete this email."
	}
	body := fmt.Sprintf(`<div style="font-family:Arial,sans-serif;font-size:16px;color:#22191a;line-height:1.5">`+
		`<p>%s</p><p style="font-size:32px;font-weight:700;letter-spacing:6px;margin:16px 0">%s</p>`+
		`<p style="color:#524344;font-size:14px">%s</p></div>`, html.EscapeString(intro), code, html.EscapeString(outro))
	return subject, body
}
