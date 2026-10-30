package migrations

import (
	m "github.com/pocketbase/pocketbase/migrations"
)

// live_location_mutual — точку партнёра видит только тот, кто делится сам
// (BACKLOG D11, domain/access).
func init() {
	m.Register(ApplyRules, nil, liveLocationMutualFile)
}

// Номер с запасом: параллельные пункты волны 3 занимают соседние.
const liveLocationMutualFile = "1760000031_live_location_mutual.go"
