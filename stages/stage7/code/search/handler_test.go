package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
)

func TestSearchCacheLifecycle(t *testing.T) {
	cache := miniredis.RunT(t)
	t.Setenv("REDIS_URL", "redis://"+cache.Addr())
	t.Setenv("CACHE_ENABLED", "true")
	redisClient = nil
	t.Cleanup(func() {
		if redisClient != nil {
			redisClient.Close()
			redisClient = nil
		}
	})
	var calls atomic.Int32
	var seats atomic.Int32
	seats.Store(2)
	var broken atomic.Bool
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		if broken.Load() {
			http.Error(w, "unavailable", 503)
			return
		}
		fmt.Fprintf(w, `{"flights":[{"id":"flight-1","flightNumber":"AA101","origin":"BOM","destination":"SIN","departureTime":"2026-10-22T10:00:00Z","arrivalTime":"2026-10-22T12:00:00Z","availableSeats":%d,"status":"SCHEDULED"}]}`, seats.Load())
	}))
	defer upstream.Close()
	previous := flightServiceURL
	flightServiceURL = upstream.URL
	t.Cleanup(func() { flightServiceURL = previous })
	router := newRouter()
	request := func() *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", "/api/search?origin=BOM&destination=SIN&date=2026-10-22", nil))
		return w
	}
	first := request()
	if first.Code != 200 || first.Header().Get("X-Cache") != "MISS" {
		t.Fatalf("first response: %d %s", first.Code, first.Body)
	}
	seats.Store(1)
	hit := request()
	if hit.Header().Get("X-Cache") != "HIT" || hit.Body.String() != first.Body.String() || calls.Load() != 1 {
		t.Fatal("cache did not preserve snapshot")
	}
	cache.FastForward(time.Duration(cacheTTLSeconds+1) * time.Second)
	expired := request()
	if expired.Header().Get("X-Cache") != "MISS" || expired.Body.String() == first.Body.String() {
		t.Fatal("expired cache did not refresh availability")
	}
	cache.FlushAll()
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if got := request(); got.Code != 200 {
				t.Errorf("concurrent response %d", got.Code)
			}
		}()
	}
	wg.Wait()
	// No singleflight guarantee: concurrent cold misses may reach Flight more than once.
	cache.FlushAll()
	broken.Store(true)
	if request().Code != 502 || len(cache.Keys()) != 0 {
		t.Fatal("upstream errors must not be cached")
	}
	broken.Store(false)
	cache.SetError("ERR simulated cache outage")
	if got := request(); got.Code != 200 || got.Header().Get("X-Cache") != "MISS" {
		t.Fatal("cache outage broke search")
	}
	cache.SetError("")
	if request().Code != 200 || request().Header().Get("X-Cache") != "HIT" {
		t.Fatal("cache did not recover")
	}
}
