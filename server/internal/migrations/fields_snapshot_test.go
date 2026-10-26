package migrations_test

import (
	"encoding/json"
	"flag"
	"os"
	"slices"
	"testing"

	"github.com/stretchr/testify/require"
)

var updateFields = flag.Bool("update-fields", false, "переписать testdata/fields.json")

// fieldsSnapshot — итоговая схема после всех миграций: коллекция → поля.
// Приложение сверяет с ним то, что пишет (test/support/fork_schema.dart):
// PocketBase молча выбрасывает поле, которого нет в схеме.
const fieldsSnapshot = "testdata/fields.json"

// Снимок схемы не отстаёт от миграций. Обновить:
//
//	go test ./internal/migrations -run TestFieldsSnapshot -update-fields
func TestFieldsSnapshot(t *testing.T) {
	app := newApp(t)
	cols, err := app.FindAllCollections()
	require.NoError(t, err)
	got := map[string][]string{}
	for _, c := range cols {
		if c.System {
			continue
		}
		var names []string
		for _, f := range c.Fields {
			names = append(names, f.GetName())
		}
		slices.Sort(names)
		got[c.Name] = names
	}
	raw, err := json.MarshalIndent(got, "", "  ")
	require.NoError(t, err)
	raw = append(raw, '\n')
	if *updateFields {
		require.NoError(t, os.WriteFile(fieldsSnapshot, raw, 0o644))
	}
	want, err := os.ReadFile(fieldsSnapshot)
	require.NoError(t, err, "нет снимка: запустите с -update-fields")
	require.JSONEq(t, string(want), string(raw), "схема изменилась: запустите с -update-fields")
}
