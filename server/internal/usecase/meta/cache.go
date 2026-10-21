package meta

import (
	"container/list"
	"sync"
	"time"
)

// cache — LRU с TTL и потолком по байтам. Только в памяти: после рестарта
// провайдеры просто спрашиваются заново.
type cache struct {
	mu       sync.Mutex
	maxBytes int
	size     int
	ll       *list.List
	items    map[string]*list.Element
}

type entry struct {
	key     string
	value   Response
	expires time.Time
}

func newCache(maxBytes int) *cache {
	return &cache{maxBytes: maxBytes, ll: list.New(), items: map[string]*list.Element{}}
}

func (c *cache) get(key string, now time.Time) (Response, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	el, ok := c.items[key]
	if !ok {
		return Response{}, false
	}
	e := el.Value.(*entry)
	if now.After(e.expires) {
		c.remove(el)
		return Response{}, false
	}
	c.ll.MoveToFront(el)
	return e.value, true
}

func (c *cache) put(key string, v Response, ttl time.Duration, now time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if el, ok := c.items[key]; ok {
		c.remove(el)
	}
	if len(v.Body) > c.maxBytes {
		return
	}
	c.items[key] = c.ll.PushFront(&entry{key: key, value: v, expires: now.Add(ttl)})
	c.size += len(v.Body)
	for c.size > c.maxBytes {
		c.remove(c.ll.Back())
	}
}

func (c *cache) remove(el *list.Element) {
	e := el.Value.(*entry)
	c.ll.Remove(el)
	delete(c.items, e.key)
	c.size -= len(e.value.Body)
}
