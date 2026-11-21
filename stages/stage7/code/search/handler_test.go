package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
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
	resetRedisClient()
	t.Cleanup(resetRedisClient)
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

func TestSearchCacheDisabled(t *testing.T) {
	t.Setenv("CACHE_ENABLED", "false")
	t.Setenv("REDIS_URL", "invalid-url-ignored")
	resetRedisClient()
	t.Cleanup(resetRedisClient)
	var calls atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		fmt.Fprint(w, `{"flights":[{"id":"flight-1","flightNumber":"AA101","origin":"BOM","destination":"SIN","departureTime":"2026-10-22T10:00:00Z","arrivalTime":"2026-10-22T12:00:00Z","availableSeats":5,"status":"SCHEDULED"}]}`)
	}))
	defer upstream.Close()
	previous := flightServiceURL
	flightServiceURL = upstream.URL
	t.Cleanup(func() { flightServiceURL = previous })
	router := newRouter()
	for i := 0; i < 2; i++ {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", "/api/search?origin=BOM&destination=SIN&date=2026-10-22", nil))
		if w.Code != 200 || w.Header().Get("X-Cache") != "MISS" {
			t.Fatalf("call %d: expected 200 MISS, got %d %s", i+1, w.Code, w.Header().Get("X-Cache"))
		}
	}
	if calls.Load() != 2 {
		t.Fatalf("expected 2 upstream calls when cache disabled, got %d", calls.Load())
	}
}

func TestSearchInvalidDateReturnsBadRequest(t *testing.T) {
	t.Setenv("CACHE_ENABLED", "false")
	resetRedisClient()
	t.Cleanup(resetRedisClient)
	router := newRouter()
	w := httptest.NewRecorder()
	router.ServeHTTP(w, httptest.NewRequest("GET", "/api/search?origin=BOM&destination=SIN&date=2026-99-99", nil))
	if w.Code != 400 {
		t.Fatalf("expected 400 for invalid date, got %d: %s", w.Code, w.Body.String())
	}
}

func TestSearchCustomCacheTTLSeconds(t *testing.T) {
	cache := miniredis.RunT(t)
	t.Setenv("REDIS_URL", "redis://"+cache.Addr())
	t.Setenv("CACHE_ENABLED", "true")
	t.Setenv("CACHE_TTL_SECONDS", "5")
	resetRedisClient()
	t.Cleanup(resetRedisClient)
	var calls atomic.Int32
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		calls.Add(1)
		fmt.Fprint(w, `{"flights":[{"id":"flight-1","flightNumber":"AA101","origin":"BOM","destination":"SIN","departureTime":"2026-10-22T10:00:00Z","arrivalTime":"2026-10-22T12:00:00Z","availableSeats":5,"status":"SCHEDULED"}]}`)
	}))
	defer upstream.Close()
	previous := flightServiceURL
	flightServiceURL = upstream.URL
	t.Cleanup(func() { flightServiceURL = previous })
	router := newRouter()
	req := func() *httptest.ResponseRecorder {
		w := httptest.NewRecorder()
		router.ServeHTTP(w, httptest.NewRequest("GET", "/api/search?origin=BOM&destination=SIN&date=2026-10-22", nil))
		return w
	}
	if first := req(); first.Code != 200 || first.Header().Get("X-Cache") != "MISS" {
		t.Fatalf("first: %d %s", first.Code, first.Header().Get("X-Cache"))
	}
	if hit := req(); hit.Header().Get("X-Cache") != "HIT" {
		t.Fatalf("expected HIT before custom TTL expiry, got %s", hit.Header().Get("X-Cache"))
	}
	cache.FastForward(6 * time.Second)
	if after := req(); after.Header().Get("X-Cache") != "MISS" || calls.Load() != 2 {
		t.Fatalf("expected MISS and upstream refresh after 5s custom TTL, got %s calls=%d", after.Header().Get("X-Cache"), calls.Load())
	}
}

func TestSearchJSONLogIncludesRequestID(t *testing.T) {
	t.Setenv("CACHE_ENABLED", "false")
	resetRedisClient()
	t.Cleanup(resetRedisClient)
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, `{"flights":[]}`)
	}))
	defer upstream.Close()
	previous := flightServiceURL
	flightServiceURL = upstream.URL
	t.Cleanup(func() { flightServiceURL = previous })

	var buf bytes.Buffer
	logger.SetOutput(&buf)
	t.Cleanup(func() { logger.SetOutput(os.Stdout) })

	router := newRouter()
	r := httptest.NewRequest("GET", "/api/search?origin=BOM&destination=SIN&date=2026-10-22", nil)
	r.Header.Set("X-Request-ID", "req-log-test-123")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, r)
	if w.Code != 200 {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	found := false
	for _, line := range strings.Split(strings.TrimSpace(buf.String()), "\n") {
		if line == "" {
			continue
		}
		var entry map[string]interface{}
		if err := json.Unmarshal([]byte(line), &entry); err == nil && entry["request_id"] == "req-log-test-123" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("expected JSON log line with request_id=req-log-test-123, got logs:\n%s", buf.String())
	}
}
