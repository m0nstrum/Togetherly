package pocketbase_test

import (
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Прямой PATCH пары: уйти можно только самому, добавить нельзя, в словарях
// участников — только свой ключ, поля ожидания закрыты.
func TestGroupsGuard(t *testing.T) {
	w := newWorld(t)
	g, err := w.app.FindRecordById("groups", pairA)
	require.NoError(t, err)
	g.Set("member_names", map[string]any{alice: "e2e1.a", bob: "e2e1.b"})
	require.NoError(t, w.app.Save(g))
	path := "/api/collections/groups/records/" + pairA
	patch := func(tok, body string) int {
		code, _ := w.do(t, http.MethodPatch, path, tok, body)
		return code
	}
	assert.Equal(t, http.StatusForbidden, patch(w.aTok, `{"members":["`+alice+`"]}`), "выкинуть партнёра")
	assert.Equal(t, http.StatusForbidden, patch(w.aTok, `{"members":["`+alice+`","`+bob+`","`+eve+`"]}`), "вписать")
	assert.Equal(t, http.StatusForbidden, patch(w.aTok, `{"member_names":{"`+alice+`":"e2e1.x","`+bob+`":"e2e1.fake"}}`))
	assert.Equal(t, http.StatusForbidden, patch(w.aTok, `{"member_names":{"`+alice+`":"e2e1.x"}}`), "стереть чужой ключ")
	assert.Equal(t, http.StatusForbidden, patch(w.aTok, `{"claim_token":"x"}`))
	assert.Equal(t, http.StatusForbidden, patch(w.aTok, `{"claim_token:autogenerate":""}`), "модификатор")
	assert.Equal(t, http.StatusForbidden, patch(w.aTok, `{"members+":["`+eve+`"]}`), "модификатор")
	assert.Equal(t, http.StatusOK, patch(w.aTok, `{"member_names":{"`+bob+`":"e2e1.b","`+alice+`":"e2e1.x"}}`), "свой ключ")

	// Ушла сама — пара пропала из её быстрых правил, у партнёра осталась.
	require.Equal(t, http.StatusOK, patch(w.aTok, `{"members":["`+bob+`"]}`))
	a, err := w.app.FindRecordById("users", alice)
	require.NoError(t, err)
	assert.NotContains(t, a.GetStringSlice("group_ids"), pairA)
	b, err := w.app.FindRecordById("users", bob)
	require.NoError(t, err)
	assert.Contains(t, b.GetStringSlice("live_group_ids"), pairA)

	// Распад: из live_group_ids уходит, в group_ids остаётся.
	g, err = w.app.FindRecordById("groups", pairA)
	require.NoError(t, err)
	g.Set("disbanded", true)
	require.NoError(t, w.app.Save(g))
	b, err = w.app.FindRecordById("users", bob)
	require.NoError(t, err)
	assert.NotContains(t, b.GetStringSlice("live_group_ids"), pairA)
	assert.Contains(t, b.GetStringSlice("group_ids"), pairA)
}
