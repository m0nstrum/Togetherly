package records_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/records"
)

func TestCreate(t *testing.T) {
	app := testutil.NewApp(t)
	svc := records.New(app)

	// Как «салют» из gifts.pb.js: data приходит строкой JSON.
	r, err := svc.Create(context.Background(), "memories", map[string]any{
		"group_id": "g1", "author_uid": "u1", "type": "gift", "nope": 1,
		"data": `{"type":"gift","giftKey":"salute"}`,
	})
	require.NoError(t, err)
	got, err := app.FindRecordById("memories", r.Id)
	require.NoError(t, err)
	assert.Equal(t, "gift", got.GetString("type"))
	assert.JSONEq(t, `{"type":"gift","giftKey":"salute"}`, got.GetString("data"))

	_, err = svc.Create(context.Background(), "users", map[string]any{"email": "x@example.org"})
	assert.ErrorIs(t, err, records.ErrForbidden)
	_, err = svc.Create(context.Background(), "_superusers", nil)
	assert.ErrorIs(t, err, records.ErrForbidden)
}
