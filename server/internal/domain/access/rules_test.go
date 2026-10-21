package access_test

import (
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/m0nstrum/togetherly/server/internal/domain/access"
)

// Ни одна коллекция пары не открыта анонимам и всем подряд.
func TestNoPublicPairCollections(t *testing.T) {
	public := map[string]bool{"catalog_items": true, "app_config": true, "users": true}
	for name, r := range access.Collections {
		t.Run(name, func(t *testing.T) {
			for op, rule := range map[string]*string{
				"list": r.List, "view": r.View, "create": r.Create, "update": r.Update, "delete": r.Delete,
			} {
				if rule == nil {
					continue
				}
				if public[name] && (op == "list" || op == "view" || (name == "users" && op == "create")) {
					continue
				}
				assert.NotEmpty(t, *rule, "%s.%s открыт всем", name, op)
				assert.True(t, strings.Contains(*rule, "@request.auth.id"), "%s.%s не проверяет вход", name, op)
			}
		})
	}
}
