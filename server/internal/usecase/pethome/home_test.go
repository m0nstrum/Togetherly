package pethome_test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/m0nstrum/togetherly/server/internal/testutil"
	"github.com/m0nstrum/togetherly/server/internal/usecase/pethome"
)

const (
	pair  = "grppairaaaaaaaa"
	alice = "usralice0000001"
	bob   = "usrbob000000001"
	eve   = "usreve000000001"
)

var state = "e2e1." + strings.Repeat("a", 64)

func op(n int) string { return fmt.Sprintf("%032x", n) }

func newService(t *testing.T) *pethome.Service {
	app := testutil.NewApp(t)
	testutil.Group(t, app, pair, alice, bob)
	return pethome.New(app)
}

// Сервер не расшифровывает дом, но держит форму: только шифр разумного
// размера, операция — 32 hex, версия — неотрицательная и не у предела int32.
func TestWriteRejectsMalformed(t *testing.T) {
	svc := newService(t)
	cases := map[string]struct {
		revision  int
		operation string
		state     string
	}{
		"отрицательная версия":  {-1, op(1), state},
		"версия у предела":      {2147483647, op(1), state},
		"операция не hex":       {0, strings.Repeat("z", 32), state},
		"операция короче":       {0, op(1)[:31], state},
		"открытый текст":        {0, op(1), `{"home":"plain"}` + strings.Repeat(" ", 32)},
		"шифр слишком короткий": {0, op(1), "e2e1.short"},
		"шифр больше 128 КБ":    {0, op(1), "e2e1." + strings.Repeat("a", 128<<10)},
	}
	for name, c := range cases {
		_, err := svc.Write(pair, alice, c.revision, c.operation, c.state)
		assert.ErrorIs(t, err, pethome.ErrInvalid, name)
	}
	home, err := svc.Read(pair, alice)
	require.NoError(t, err)
	assert.Nil(t, home, "ни одна неверная запись не создала дом")
}

func TestAccess(t *testing.T) {
	app := testutil.NewApp(t)
	testutil.Group(t, app, pair, alice, bob)
	svc := pethome.New(app)

	home, err := svc.Read(pair, alice)
	require.NoError(t, err)
	assert.Nil(t, home, "дома ещё нет — пусто без ошибки")

	_, err = svc.Read(pair, eve)
	assert.ErrorIs(t, err, pethome.ErrDenied, "не участник")
	_, err = svc.Read("nope", alice)
	assert.ErrorIs(t, err, pethome.ErrDenied, "пары нет")
	_, err = svc.Write(pair, eve, 0, op(1), state)
	assert.ErrorIs(t, err, pethome.ErrDenied)
	_, err = svc.Write("nope", alice, 0, op(1), state)
	assert.ErrorIs(t, err, pethome.ErrDenied)

	_, err = svc.Write(pair, alice, 0, op(1), state)
	require.NoError(t, err)
	g, err := app.FindRecordById("groups", pair)
	require.NoError(t, err)
	g.Set("disbanded", true)
	require.NoError(t, app.Save(g))
	_, err = svc.Write(pair, alice, 1, op(2), state)
	assert.ErrorIs(t, err, pethome.ErrDenied, "распавшаяся пара не пишет")
	home, err = svc.Read(pair, alice)
	require.NoError(t, err, "но архив читается")
	assert.Equal(t, 1, home.GetInt("revision"))
}

func TestFirstWriteNeedsRevisionZero(t *testing.T) {
	svc := newService(t)
	_, err := svc.Write(pair, alice, 1, op(1), state)
	assert.ErrorIs(t, err, pethome.ErrConflict, "дома нет, а клиент думает, что есть")
	home, err := svc.Write(pair, alice, 0, op(1), state)
	require.NoError(t, err)
	assert.Equal(t, 1, home.GetInt("revision"))
	assert.Equal(t, pair, home.GetString("group_id"))
	assert.Equal(t, state, home.GetString("state"))
}

// Повтор операции после потерянного ответа не тратит и не награждает второй
// раз: в ответ — текущий дом, версия не растёт, состояние не меняется.
func TestRetryIsIdempotent(t *testing.T) {
	svc := newService(t)
	_, err := svc.Write(pair, alice, 0, op(1), state)
	require.NoError(t, err)
	home, err := svc.Write(pair, bob, 1, op(2), state+"b")
	require.NoError(t, err)
	require.Equal(t, 2, home.GetInt("revision"))

	home, err = svc.Write(pair, alice, 0, op(1), state+"retry")
	require.NoError(t, err, "старая версия, но операция уже применена")
	assert.Equal(t, 2, home.GetInt("revision"))
	assert.Equal(t, state+"b", home.GetString("state"))
}

// Журнал операций держит последние 128: старше — уже не повтор, а запись со
// старой версией, то есть конфликт.
func TestOperationLogIsCapped(t *testing.T) {
	svc := newService(t)
	var ops []string
	for i := range 130 {
		home, err := svc.Write(pair, alice, i, op(i+1), state)
		require.NoError(t, err, i)
		require.NoError(t, home.UnmarshalJSONField("operations", &ops))
		require.Len(t, ops, min(i+1, 128), i)
	}
	assert.Equal(t, op(3), ops[0], "две самые старые вытеснены")
	assert.Equal(t, op(130), ops[127])

	_, err := svc.Write(pair, alice, 0, op(1), state)
	assert.ErrorIs(t, err, pethome.ErrConflict, "вытесненная операция — не повтор")
	home, err := svc.Write(pair, alice, 2, op(3), state)
	require.NoError(t, err, "ещё помнящаяся — повтор")
	assert.Equal(t, 130, home.GetInt("revision"))
}
