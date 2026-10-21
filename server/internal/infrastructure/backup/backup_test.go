package backup_test

import (
	"bytes"
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"filippo.io/age"
	"github.com/pocketbase/pocketbase/core"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/infrastructure/backup"
	"github.com/m0nstrum/togetherly/server/internal/testutil"
)

func keyFile(t *testing.T) (*age.X25519Identity, string) {
	t.Helper()
	id, err := age.GenerateX25519Identity()
	require.NoError(t, err)
	p := filepath.Join(t.TempDir(), "key.txt")
	require.NoError(t, os.WriteFile(p, []byte(id.String()+"\n"), 0o600))
	return id, p
}

// Полный цикл: бэкап → шифр → открытой копии нет → восстановление в пустой
// каталог → данные на месте.
func TestBackupRoundTrip(t *testing.T) {
	ctx := context.Background()
	app := testutil.NewApp(t)
	id, key := keyFile(t)
	dir := t.TempDir()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	require.NoError(t, backup.Bind(app, backup.Options{Dir: dir, Recipients: id.Recipient().String(), MaxKeep: 2}, log))

	testutil.User(t, app, "backupuser00001")
	require.NoError(t, app.CreateBackup(ctx, "pb_backup_20261021000001.zip"))

	enc := filepath.Join(dir, "pb_backup_20261021000001.zip"+backup.Ext)
	raw, err := os.ReadFile(enc)
	require.NoError(t, err)
	assert.False(t, bytes.Contains(raw, []byte("backupuser00001")), "в шифртексте нет открытых данных")
	st, err := os.Stat(enc)
	require.NoError(t, err)
	assert.Equal(t, os.FileMode(0o600), st.Mode().Perm())

	plain, err := app.NewBackupsFilesystem()
	require.NoError(t, err)
	exists, err := plain.Exists("pb_backup_20261021000001.zip")
	plain.Close()
	require.NoError(t, err)
	assert.False(t, exists, "открытый zip удалён")

	restored := filepath.Join(t.TempDir(), "pb_data")
	require.NoError(t, backup.Restore(enc, key, restored))
	back := core.NewBaseApp(core.BaseAppConfig{DataDir: restored, EncryptionEnv: "pb_test_env"})
	require.NoError(t, back.Bootstrap())
	defer back.ResetBootstrapState()
	u, err := back.FindRecordById("users", "backupuser00001")
	require.NoError(t, err)
	assert.Equal(t, "backupuser00001@example.org", u.Email())

	t.Run("поверх живых данных не восстанавливаем", func(t *testing.T) {
		assert.Error(t, backup.Restore(enc, key, restored))
	})
	t.Run("чужой ключ не подходит", func(t *testing.T) {
		_, other := keyFile(t)
		assert.Error(t, backup.Restore(enc, other, filepath.Join(t.TempDir(), "x")))
	})
	t.Run("ротация оставляет последние", func(t *testing.T) {
		for _, n := range []string{"pb_backup_20261022000001.zip", "pb_backup_20261023000001.zip"} {
			require.NoError(t, app.CreateBackup(ctx, n))
		}
		ents, err := os.ReadDir(dir)
		require.NoError(t, err)
		var names []string
		for _, e := range ents {
			names = append(names, e.Name())
		}
		assert.Equal(t, []string{"pb_backup_20261022000001.zip.age", "pb_backup_20261023000001.zip.age"}, names)
	})
}

func TestParseRecipients(t *testing.T) {
	a, _ := age.GenerateX25519Identity()
	b, _ := age.GenerateX25519Identity()
	r, err := backup.ParseRecipients(a.Recipient().String() + ", " + b.Recipient().String())
	require.NoError(t, err)
	assert.Len(t, r, 2)
	_, err = backup.ParseRecipients("ssh-rsa AAAA")
	assert.Error(t, err)
	_, err = backup.ParseRecipients("")
	assert.Error(t, err)
}
