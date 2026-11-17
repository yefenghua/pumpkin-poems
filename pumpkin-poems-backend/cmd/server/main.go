// Command server runs the Pumpkin Poems phase-2 API.
//
// Environment:
//
//	ADDR             listen address (default :8080)
//	DATABASE_URL     PostgreSQL URL; empty = in-memory store (data lost on restart)
//	CONTENT_DIR      content release directory (default ./content-releases)
//	ADMIN_TOKEN      bearer token for /v1/admin/*; empty disables admin endpoints
//	LOG_FORMAT       "json" (default) or "text"
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata" // metrics ?tz= works on minimal images

	"github.com/yefenghua/pumpkin-poems/backend/internal/api"
	"github.com/yefenghua/pumpkin-poems/backend/internal/content"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store/memstore"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store/pgstore"
)

func main() {
	var handler slog.Handler = slog.NewJSONHandler(os.Stderr, nil)
	if os.Getenv("LOG_FORMAT") == "text" {
		handler = slog.NewTextHandler(os.Stderr, nil)
	}
	log := slog.New(handler)
	slog.SetDefault(log)
	if err := run(log); err != nil {
		log.Error("server failed", "err", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	addr := envOr("ADDR", ":8080")
	contentDir := envOr("CONTENT_DIR", "./content-releases")
	adminToken := os.Getenv("ADMIN_TOKEN")

	var st store.Store
	if dsn := os.Getenv("DATABASE_URL"); dsn != "" {
		openCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
		pg, err := pgstore.Open(openCtx, dsn)
		cancel()
		if err != nil {
			return err
		}
		defer pg.Close()
		st = pg
		log.Info("using postgres store")
	} else {
		st = memstore.New()
		log.Warn("DATABASE_URL not set: using in-memory store, data is lost on restart")
	}
	if adminToken == "" {
		log.Warn("ADMIN_TOKEN not set: /v1/admin/metrics is disabled")
	}
	if rel, err := content.CurrentRelease(contentDir); err == nil {
		log.Info("content", "dir", contentDir, "release", rel)
	} else {
		log.Warn("no content release yet", "dir", contentDir, "err", err)
	}

	srv := &http.Server{
		Addr: addr,
		Handler: api.New(api.Config{
			Store:      st,
			Content:    content.NewRepo(contentDir),
			AdminToken: adminToken,
			Logger:     log,
		}),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       60 * time.Second,
		WriteTimeout:      60 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", addr)
		errCh <- srv.ListenAndServe()
	}()
	select {
	case err := <-errCh:
		if !errors.Is(err, http.ErrServerClosed) {
			return err
		}
		return nil
	case <-ctx.Done():
	}
	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	return srv.Shutdown(shutdownCtx)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
