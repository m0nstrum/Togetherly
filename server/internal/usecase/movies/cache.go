package movies

import (
	"container/list"
	"sync"
	"time"
)

// ttlCache — LRU с TTL и потолком по числу записей. Только в памяти: после
// рестарта Викиданные просто спрашиваются заново.
type ttlCache[V any] struct {
	mu    sync.Mutex
	max   int
	ll    *list.List
	items map[string]*list.Element
}

type ttlEntry[V any] struct {
	key     string
	value   V
	expires time.Time
}

func newTTLCache[V any](max int) *ttlCache[V] {
	return &ttlCache[V]{max: max, ll: list.New(), items: map[string]*list.Element{}}
}

func (c *ttlCache[V]) get(key string, now time.Time) (V, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	var zero V
	el, ok := c.items[key]
	if !ok {
		return zero, false
	}
	e := el.Value.(*ttlEntry[V])
	if now.After(e.expires) {
		c.ll.Remove(el)
		delete(c.items, key)
		return zero, false
	}
	c.ll.MoveToFront(el)
	return e.value, true
}

func (c *ttlCache[V]) put(key string, v V, ttl time.Duration, now time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if el, ok := c.items[key]; ok {
		c.ll.Remove(el)
	}
	c.items[key] = c.ll.PushFront(&ttlEntry[V]{key: key, value: v, expires: now.Add(ttl)})
	for c.ll.Len() > c.max {
		back := c.ll.Back()
		c.ll.Remove(back)
		delete(c.items, back.Value.(*ttlEntry[V]).key)
	}
}
