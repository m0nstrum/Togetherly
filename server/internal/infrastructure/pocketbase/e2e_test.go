package pocketbase_test

import (
	"encoding/json"
	"fmt"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func identityBody(uid string, version int) string {
	return fmt.Sprintf(`{"user_uid":%q,"account_key":"ak","version":%d,"devices":{"user":%q,"version":%d,"devices":[],"sig":"s"}}`,
		uid, version, uid, version)
}

func TestE2EIdentities(t *testing.T) {
	w := newWorld(t)
	const base = "/api/collections/e2e_identities/records"

	code, _ := w.do(t, http.MethodPost, base, w.eTok, identityBody(alice, 1))
	assert.NotEqual(t, http.StatusOK, code, "ключи от чужого имени")

	code, body := w.do(t, http.MethodPost, base, w.aTok, identityBody(alice, 1))
	require.Equal(t, http.StatusOK, code, body)
	id := jsonField(t, body, "id")

	code, _ = w.do(t, http.MethodPost, base, w.aTok, identityBody(alice, 1))
	assert.NotEqual(t, http.StatusOK, code, "вторая запись на человека")

	t.Run("видят свои и партнёр, посторонний — нет", func(t *testing.T) {
		code, _ := w.do(t, http.MethodGet, base+"/"+id, w.bTok, "")
		assert.Equal(t, http.StatusOK, code)
		code, _ = w.do(t, http.MethodGet, base+"/"+id, w.eTok, "")
		assert.NotEqual(t, http.StatusOK, code)
	})

	t.Run("версия только вперёд и совпадает со списком", func(t *testing.T) {
		code, _ := w.do(t, http.MethodPatch, base+"/"+id, w.aTok, identityBody(alice, 1))
		assert.Equal(t, http.StatusConflict, code, "та же версия")
		code, _ = w.do(t, http.MethodPatch, base+"/"+id, w.aTok,
			`{"version":3,"devices":{"user":"`+alice+`","version":2,"devices":[],"sig":"s"}}`)
		assert.Equal(t, http.StatusBadRequest, code, "версия записи ≠ версии списка")
		code, _ = w.do(t, http.MethodPatch, base+"/"+id, w.aTok, identityBody(alice, 2))
		assert.Equal(t, http.StatusOK, code)
	})

	t.Run("чужую не правит, свою не отдаёт другому", func(t *testing.T) {
		code, _ := w.do(t, http.MethodPatch, base+"/"+id, w.bTok, identityBody(alice, 5))
		assert.NotEqual(t, http.StatusOK, code)
		code, _ = w.do(t, http.MethodPatch, base+"/"+id, w.aTok, identityBody(bob, 6))
		assert.Equal(t, http.StatusForbidden, code)
	})
}

func TestE2EGrants(t *testing.T) {
	w := newWorld(t)
	const base = "/api/collections/e2e_grants/records"
	grant := func(tok, group, from, to string) (int, string) {
		return w.do(t, http.MethodPost, base, tok,
			fmt.Sprintf(`{"group_id":%q,"user_uid":%q,"to_uid":%q,"to_device":"d1","epoch":1,"data":{}}`, group, from, to))
	}

	code, body := grant(w.aTok, pairA, alice, bob)
	require.Equal(t, http.StatusOK, code, body)
	id := jsonField(t, body, "id")

	code, _ = grant(w.aTok, pairA, alice, eve)
	assert.Equal(t, http.StatusForbidden, code, "ключ пары постороннему")
	code, _ = grant(w.eTok, pairA, eve, bob)
	assert.NotEqual(t, http.StatusOK, code, "посторонний выдаёт ключ чужой пары")
	code, _ = grant(w.aTok, pairA, bob, alice)
	assert.NotEqual(t, http.StatusOK, code, "от чужого имени")
	code, _ = grant(w.aTok, pairA, alice, bob)
	assert.NotEqual(t, http.StatusOK, code, "та же эпоха тому же устройству")

	code, _ = w.do(t, http.MethodGet, base+"/"+id, w.bTok, "")
	assert.Equal(t, http.StatusOK, code, "получатель")
	code, _ = w.do(t, http.MethodGet, base+"/"+id, w.eTok, "")
	assert.NotEqual(t, http.StatusOK, code, "посторонний")
	code, _ = w.do(t, http.MethodPatch, base+"/"+id, w.aTok, `{"epoch":2}`)
	assert.NotEqual(t, http.StatusOK, code, "выдача неизменна")
}

func TestE2EBackupOnlyOwn(t *testing.T) {
	w := newWorld(t)
	const base = "/api/collections/e2e_backups/records"
	code, body := w.do(t, http.MethodPost, base, w.aTok, `{"user_uid":"`+alice+`","data":{"ct":"x"}}`)
	require.Equal(t, http.StatusOK, code, body)
	id := jsonField(t, body, "id")
	code, _ = w.do(t, http.MethodGet, base+"/"+id, w.bTok, "")
	assert.NotEqual(t, http.StatusOK, code, "бэкап ключей партнёру не виден")
	code, _ = w.do(t, http.MethodPost, base, w.bTok, `{"user_uid":"`+alice+`","data":{}}`)
	assert.NotEqual(t, http.StatusOK, code)
}

func jsonField(t *testing.T, body, key string) string {
	t.Helper()
	var m map[string]any
	require.NoError(t, json.Unmarshal([]byte(body), &m), body)
	v, _ := m[key].(string)
	require.NotEmpty(t, v, body)
	return v
}
