package migrations

import (
	m "github.com/pocketbase/pocketbase/migrations"
)

// live_location_channel_fixed — канал своей точки не переписывается
// (domain/access, live_location.Update): иначе подписка на прежний геоканал
// жила бы до истечения токена.
func init() {
	m.Register(ApplyRules, nil, liveLocationChannelFixedFile)
}

const liveLocationChannelFixedFile = "1760000032_live_location_channel_fixed.go"
