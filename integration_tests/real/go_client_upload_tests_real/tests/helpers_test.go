package tests

import (
	"context"
	"testing"
	"time"
)

func ctx(t *testing.T) context.Context {
	t.Helper()
	c, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	t.Cleanup(cancel)
	return c
}

func must[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}
