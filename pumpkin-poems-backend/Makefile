APP_DIR      ?= ../pumpkin-poems-app
PACKS        ?= $(APP_DIR)/build/packs
REVIEW       ?= $(APP_DIR)/content/review-status.json
CONTENT_DIR  ?= ./content-releases
RELEASE      ?= $(shell date -u +%Y-%m-%d).1
PG_PORT      ?= 5432
DEV_DB       ?= postgres://pumpkin:pumpkin@localhost:$(PG_PORT)/pumpkin?sslmode=disable
TEST_DB      ?= postgres://pumpkin:pumpkin@localhost:$(PG_PORT)/pumpkin_test?sslmode=disable

.PHONY: run run-pg test test-pg vet validate publish-dev list db-up db-down

# In-memory store, for the simulator. Register any account from the app's 家长区域.
run:
	ADMIN_TOKEN=dev-admin CONTENT_DIR=$(CONTENT_DIR) go run ./cmd/server

run-pg:
	DATABASE_URL='$(DEV_DB)' ADMIN_TOKEN=dev-admin CONTENT_DIR=$(CONTENT_DIR) go run ./cmd/server

vet:
	go vet ./...

test: vet
	go test ./...

test-pg: vet
	TEST_DATABASE_URL='$(TEST_DB)' go test -count=1 ./...

validate:
	go run ./cmd/contentctl validate --packs $(PACKS) --review $(REVIEW)

# Trial build: teacher review is not done yet, hence --allow-unreviewed.
publish-dev:
	go run ./cmd/contentctl publish --packs $(PACKS) --review $(REVIEW) --out $(CONTENT_DIR) \
		--release $(RELEASE) --allow-unreviewed

list:
	go run ./cmd/contentctl list --out $(CONTENT_DIR)

db-up:
	PG_PORT=$(PG_PORT) docker compose up -d

db-down:
	docker compose down
