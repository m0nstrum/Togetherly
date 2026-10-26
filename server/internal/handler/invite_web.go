package handler

import (
	"html/template"
	"net/http"
	"regexp"
	"strings"
	"unicode"

	"github.com/pocketbase/dbx"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/router"
)

// InvitePage — что нужно странице приглашения и проверке ссылок приложения.
// Пустые адреса магазинов не показываются; без пакета и отпечатков Android
// и без appID iOS файлы проверки домена не раздаются.
type InvitePage struct {
	AppName string
	// Scheme — схема приложения: <scheme>://invite/<код>.
	Scheme              string
	PlayURL             string
	RuStoreURL          string
	APKURL              string
	AndroidPackage      string
	AndroidFingerprints []string
	IOSAppID            string // TeamID.BundleID
}

var inviteCodeChars = regexp.MustCompile(`[^A-Za-z0-9]`)

// inviterName — имя для публичной страницы: только буквы, цифры, пробел и
// дефис, не длиннее 24 знаков. Шифр (E2E) не показываем.
func inviterName(raw string) string {
	raw = strings.TrimSpace(raw)
	if strings.HasPrefix(raw, "e2e1.") {
		return ""
	}
	out := []rune{}
	for _, r := range raw {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == ' ' || r == '-' {
			out = append(out, r)
		}
	}
	name := strings.TrimSpace(string(out))
	if r := []rune(name); len(r) > 24 {
		name = strings.TrimSpace(string(r[:24]))
	}
	return name
}

var invitePageTmpl = template.Must(template.New("invite").Parse(`<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Приглашение в {{.App}}</title>
<style>body{font-family:-apple-system,Segoe UI,Roboto,sans-serif;background:#fff5f7;color:#33202a;display:flex;min-height:100vh;margin:0;align-items:center;justify-content:center;text-align:center}
.card{max-width:340px;padding:28px}.code{font-size:34px;font-weight:800;letter-spacing:8px;color:#e5578a;margin:14px 0}
.btn{display:inline-block;margin-top:18px;padding:14px 26px;border-radius:14px;background:#e5578a;color:#fff;text-decoration:none;font-weight:700}
.store{display:block;margin:10px auto 0;max-width:260px;padding:13px 20px;border-radius:14px;background:#fff;border:1px solid #f0c9d6;color:#33202a;text-decoration:none;font-weight:600}
.hint{margin-top:24px;font-size:13px;color:#7a5c67;line-height:1.5}
.who{width:64px;height:64px;border-radius:50%;background:#ffd9de;color:#90003b;display:flex;align-items:center;justify-content:center;font-size:26px;font-weight:800;margin:0 auto 14px}
</style></head><body><div class="card">
{{if .Code}}{{if .Name}}<div class="who">{{.Initial}}</div><h2>{{.Name}} зовёт вас в {{.App}}</h2>{{else}}<h2>💞 Тебя приглашают в {{.App}}</h2>{{end}}
<p>Одно приложение на двоих: общий чат, настроение, лента воспоминаний и виджеты на экране.</p>
<p style="margin-top:18px">Код приглашения:</p><div class="code">{{.Code}}</div>
<p>Открываем приложение…</p>
<a class="btn" id="open" href="{{.Deep}}">Открыть в приложении</a>
<p class="hint">Приложения ещё нет? Поставьте — код подхватится сам.</p>
{{else}}<h2>В ссылке нет кода</h2>
<p>Её отправили раньше, чем приложение успело получить код приглашения.</p>
<p>Попросите партнёра открыть раздел «Связь» и прислать ссылку заново — там же виден и сам код, его можно ввести руками.</p>
<a class="btn" href="{{.Deep}}">Открыть {{.App}}</a>
<p class="hint">Приложения ещё нет? Поставьте, а код введёте после входа.</p>
{{end}}{{range .Stores}}<a class="store" href="{{.URL}}">{{.Label}}</a>
{{end}}</div>{{if .Code}}<script>
// Во фрагменте — секрет приглашения (E2E): на сервер он не уходит, а
// приложению нужен, поэтому дописываем его к ссылке здесь.
var deep={{.Deep}}+(location.hash||"");document.getElementById("open").href=deep;
setTimeout(function(){location.href=deep},400);
</script>{{end}}</body></html>`))

// InviteWeb — веб-часть приглашений (бывший invite_web.pb.js):
//
//	GET /invite/{code} — страница: пробует открыть приложение, иначе магазины;
//	GET /invite[/]     — ссылка без кода (её рассылали, пока приложение не
//	                     получило код): объяснение и путь дальше;
//	GET /.well-known/assetlinks.json, /.well-known/apple-app-site-association —
//	                     проверка домена для ссылок приложения.
//
// Из базы читается только имя пригласившего — оно делает страницу
// человеческой. Код очищается до 12 латинских букв и цифр.
func InviteWeb(r *router.Router[*core.RequestEvent], p InvitePage) {
	type store struct{ URL, Label string }
	var stores []store
	for _, s := range []store{{p.PlayURL, "Google Play"}, {p.RuStoreURL, "RuStore"}, {p.APKURL, "Скачать APK"}} {
		if s.URL != "" {
			stores = append(stores, s)
		}
	}
	page := func(e *core.RequestEvent, code string) error {
		deep := p.Scheme + "://invite"
		name := ""
		if code != "" {
			deep += "/" + code
			var row struct {
				Name string `db:"nm"`
			}
			err := e.App.DB().NewQuery(`SELECT u.display_name AS nm FROM invite_codes ic
				JOIN users u ON u.id = ic.owner_uid WHERE ic.code = {:c} LIMIT 1`).
				Bind(dbx.Params{"c": code}).One(&row)
			if err == nil {
				name = inviterName(row.Name)
			}
		}
		initial := ""
		if r := []rune(name); len(r) > 0 {
			initial = strings.ToUpper(string(r[0]))
		}
		e.Response.Header().Set("Content-Type", "text/html; charset=utf-8")
		e.Response.WriteHeader(http.StatusOK)
		return invitePageTmpl.Execute(e.Response, map[string]any{
			"App": p.AppName, "Code": code, "Name": name, "Initial": initial,
			// Схема своя, не http: html/template её иначе вырежет.
			"Deep": template.URL(deep), "Stores": stores,
		})
	}
	r.GET("/invite", func(e *core.RequestEvent) error { return page(e, "") })
	r.GET("/invite/{code...}", func(e *core.RequestEvent) error {
		raw := inviteCodeChars.ReplaceAllString(e.Request.PathValue("code"), "")
		code := strings.ToUpper(raw[:min(len(raw), 12)])
		if code == "" && e.Request.PathValue("code") != "" {
			e.Response.Header().Set("Content-Type", "text/html; charset=utf-8")
			e.Response.WriteHeader(http.StatusBadRequest)
			_, err := e.Response.Write([]byte("<h1>Неверная ссылка приглашения</h1>"))
			return err
		}
		return page(e, code)
	})

	if p.IOSAppID != "" {
		r.GET("/.well-known/apple-app-site-association", func(e *core.RequestEvent) error {
			return e.JSON(http.StatusOK, map[string]any{"applinks": map[string]any{
				"apps": []string{},
				"details": []map[string]any{{
					"appIDs": []string{p.IOSAppID}, "appID": p.IOSAppID,
					"components": []map[string]any{{"/": "/invite/*", "comment": "invite deep links"}},
					"paths":      []string{"/invite/*"},
				}},
			}})
		})
	}
	if p.AndroidPackage != "" && len(p.AndroidFingerprints) > 0 {
		r.GET("/.well-known/assetlinks.json", func(e *core.RequestEvent) error {
			return e.JSON(http.StatusOK, []map[string]any{{
				"relation": []string{"delegate_permission/common.handle_all_urls", "delegate_permission/common.get_login_creds"},
				"target": map[string]any{
					"namespace": "android_app", "package_name": p.AndroidPackage,
					"sha256_cert_fingerprints": p.AndroidFingerprints,
				},
			}})
		})
	}
}
