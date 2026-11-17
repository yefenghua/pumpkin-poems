package pgstore_test

import (
	"context"
	"os"
	"testing"

	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store/pgstore"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store/storetest"
)

// TestConformance needs a disposable database, e.g.
//
//	TEST_DATABASE_URL=postgres://pumpkin:pumpkin@localhost:5432/pumpkin_test?sslmode=disable
//
// Every subtest truncates all tables.
func TestConformance(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	s, err := pgstore.Open(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(s.Close)
	// Running migrations twice must be a no-op.
	if err := pgstore.Migrate(ctx, s.Pool()); err != nil {
		t.Fatal(err)
	}
	storetest.Run(t, func(t *testing.T) store.Store {
		_, err := s.Pool().Exec(ctx, `TRUNCATE analytics_events, feedback, parents, sessions, profiles, sync_events, sync_drafts`)
		if err != nil {
			t.Fatal(err)
		}
		return s
	})
}
