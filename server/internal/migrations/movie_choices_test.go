package migrations_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestMovieChoicesBelongToTheirVoter(t *testing.T) {
	f := newFixture(t)
	defer f.app.Cleanup()
	base := "/api/collections/fork_movie_choices/records"
	code, response := call(t, f.app, http.MethodPost, base, f.aliceTok,
		`{"group_id":"`+pairA+`","author_uid":"`+f.alice.Id+`","movie_tag":"shared-movie","state":"opaque"}`)
	require.Equal(t, http.StatusOK, code, response)
	var record struct {
		ID string `json:"id"`
	}
	require.NoError(t, json.Unmarshal([]byte(response), &record))
	code, _ = call(t, f.app, http.MethodPatch, base+"/"+record.ID, f.aliceTok, `{"state":"new-encrypted-vote"}`)
	assert.Equal(t, http.StatusOK, code, "voter can change their own decision")
	for _, body := range []string{`{"author_uid":"` + f.bob.Id + `"}`, `{"group_id":"` + pairB + `"}`, `{"movie_tag":"replacement"}`} {
		code, _ = call(t, f.app, http.MethodPatch, base+"/"+record.ID, f.aliceTok, body)
		assert.NotEqual(t, http.StatusOK, code, "metadata must remain immutable")
	}
	bobToken, err := f.bob.NewAuthToken()
	require.NoError(t, err)
	code, _ = call(t, f.app, http.MethodGet, base+"/"+record.ID, bobToken, "")
	assert.Equal(t, http.StatusOK, code)
	code, _ = call(t, f.app, http.MethodPatch, base+"/"+record.ID, bobToken, `{"state":"forged-vote"}`)
	assert.NotEqual(t, http.StatusOK, code)
	code, _ = call(t, f.app, http.MethodDelete, base+"/"+record.ID, bobToken, "")
	assert.NotEqual(t, http.StatusNoContent, code)
	code, _ = call(t, f.app, http.MethodPost, base, bobToken,
		`{"group_id":"`+pairA+`","author_uid":"`+f.bob.Id+`","movie_tag":"shared-movie","state":"other-vote"}`)
	assert.Equal(t, http.StatusOK, code, "each partner has an independent vote")
	f.alice.Set("live_group_ids", []string{})
	require.NoError(t, f.app.Save(f.alice))
	code, _ = call(t, f.app, http.MethodPatch, base+"/"+record.ID, f.aliceTok, `{"state":"former-member"}`)
	assert.NotEqual(t, http.StatusOK, code)
}
