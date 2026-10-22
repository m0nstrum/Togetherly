package pocketbase

import (
	"context"
	"errors"
	"slices"

	"github.com/pocketbase/pocketbase/core"

	"github.com/m0nstrum/togetherly/server/internal/handler"
	"github.com/m0nstrum/togetherly/server/internal/infrastructure/centrifugo"
	"github.com/m0nstrum/togetherly/server/internal/usecase/ring"
)

// ringPublisher — зов уходит и сокетом, и будильником FCM. Сервер без
// Centrifugo всё равно будит телефон пушем — это не сбой зова.
type ringPublisher struct{ pub handler.Publisher }

func (p ringPublisher) Publish(ctx context.Context, channel string, data any) error {
	if err := p.pub.Publish(ctx, channel, data); err != nil && !errors.Is(err, centrifugo.ErrDisabled) {
		return err
	}
	return nil
}

// ringPairs — партнёр по записи groups.
type ringPairs struct{ app core.App }

func (p ringPairs) Partner(_ context.Context, groupID, uid string) (string, error) {
	g, err := p.app.FindRecordById("groups", groupID)
	if err != nil {
		return "", ring.ErrNotMember
	}
	members := g.GetStringSlice("members")
	if !slices.Contains(members, uid) {
		return "", ring.ErrNotMember
	}
	for _, m := range members {
		if m != "" && m != uid {
			return m, nil
		}
	}
	return "", ring.ErrNotMember
}
