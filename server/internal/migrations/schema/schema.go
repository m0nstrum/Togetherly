// Package schema встраивает схему коллекций апстрима.
//
// Файл — копия pocketbase/collections_schema.json: go:embed не достаёт за
// пределы модуля. Копию обновляет go generate, а тест в пакете migrations
// валится, если она разошлась с оригиналом (например, после мёржа апстрима).
package schema

import _ "embed"

//go:generate cp ../../../../pocketbase/collections_schema.json collections_schema.json

// UpstreamJSON — {"collections": [...], "deleteMissing": false}.
//
//go:embed collections_schema.json
var UpstreamJSON []byte
