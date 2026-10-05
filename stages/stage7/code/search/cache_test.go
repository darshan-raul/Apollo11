package main

import (
	"context"
	"testing"
	"time"
)

func TestCacheDisabledSkipsInvalidRedisConfiguration(t *testing.T) {
	t.Setenv("CACHE_ENABLED", "false")
	t.Setenv("REDIS_URL", "this is not a redis URL")
	client, err := getRedisClient(context.Background(), time.Second)
	if err != nil || client != nil {
		t.Fatalf("disabled cache attempted Redis initialization: client=%v err=%v", client, err)
	}
}

func TestCacheEnabledRejectsInvalidRedisConfiguration(t *testing.T) {
	t.Setenv("CACHE_ENABLED", "true")
	t.Setenv("REDIS_URL", "this is not a redis URL")
	client, err := getRedisClient(context.Background(), time.Second)
	if err == nil || client != nil {
		t.Fatalf("enabled cache did not validate Redis configuration: client=%v err=%v", client, err)
	}
}
