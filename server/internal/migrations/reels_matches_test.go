package migrations_test

import (
	"encoding/json"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"net/http"
	"testing"
)

func TestReelMatchesAreMemberAuthoredAndAppendOnly(t *testing.T) {
	f := newFixture(t)
	defer f.app.Cleanup()
	base := "/api/collections/fork_reels_matches/records"
	body := `{"group_id":"` + pairA + `","author_uid":"` + f.alice.Id + `","match_tag":"same-clip","state":"e2e:opaque"}`
	code, response := call(t, f.app, http.MethodPost, base, f.aliceTok, body)
	require.Equal(t, http.StatusOK, code, response)
	var record struct {
		ID string `json:"id"`
	}
	require.NoError(t, json.Unmarshal([]byte(response), &record))
	require.NotEmpty(t, record.ID)
	code, _ = call(t, f.app, http.MethodPost, base, f.aliceTok, body)
	assert.Equal(t, http.StatusBadRequest, code, "same tag must not create duplicates")
	code, _ = call(t, f.app, http.MethodPatch, base+"/"+record.ID, f.aliceTok, `{"author_uid":"`+f.bob.Id+`","state":"changed"}`)
	assert.Equal(t, http.StatusForbidden, code, "matches cannot be rewritten")
	code, _ = call(t, f.app, http.MethodPost, base, f.aliceTok,
		`{"group_id":"`+pairA+`","author_uid":"`+f.bob.Id+`","match_tag":"forged","state":"opaque"}`)
	assert.NotEqual(t, http.StatusOK, code, "cannot create as partner")
	code, _ = call(t, f.app, http.MethodGet, base+"/"+record.ID, f.eveTok, "")
	assert.NotEqual(t, http.StatusOK, code)
	bobToken, err := f.bob.NewAuthToken()
	require.NoError(t, err)
	code, _ = call(t, f.app, http.MethodGet, base+"/"+record.ID, bobToken, "")
	assert.Equal(t, http.StatusOK, code, "partner can read")
	code, _ = call(t, f.app, http.MethodDelete, base+"/"+record.ID, bobToken, "")
	assert.Equal(t, http.StatusNoContent, code, "partner can remove a shared match")
}
