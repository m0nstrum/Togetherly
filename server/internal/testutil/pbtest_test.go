package testutil_test

import (
	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/require"
	"testing"
)

func TestSnapshotClonesAreIsolated(t *testing.T) {
	a := testutil.NewApp(t)
	col, err := a.FindCollectionByNameOrId("groups")
	require.NoError(t, err)
	r := core.NewRecord(col)
	r.Set("members", []string{"alice"})
	require.NoError(t, a.Save(r))
	col.UpdateRule = nil
	require.NoError(t, a.Save(col))
	b := testutil.NewApp(t)
	require.NotEqual(t, a.DataDir(), b.DataDir())
	_, err = b.FindRecordById("groups", r.Id)
	require.Error(t, err, "records must not cross fixtures")
	fresh, err := b.FindCollectionByNameOrId("groups")
	require.NoError(t, err)
	require.NotNil(t, fresh.UpdateRule, "schema mutations must not cross fixtures")
}
