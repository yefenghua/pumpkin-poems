package memstore_test

import (
	"testing"

	"github.com/yefenghua/pumpkin-poems/backend/internal/store"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store/memstore"
	"github.com/yefenghua/pumpkin-poems/backend/internal/store/storetest"
)

func TestConformance(t *testing.T) {
	storetest.Run(t, func(*testing.T) store.Store { return memstore.New() })
}
