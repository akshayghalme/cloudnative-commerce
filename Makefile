# Makefile for cloudnative-commerce
# Usage: make <target>
# Run `make help` to see all available targets

.PHONY: help lint lint-docker lint-terraform lint-python lint-go \
        test test-api test-worker \
        build build-api build-storefront build-worker \
        compose-up compose-down compose-logs compose-ps \
        pre-commit-install pre-commit-run \
        clean

# ─── Default target ──────────────────────────────────────────────────────────

.DEFAULT_GOAL := help

# ─── Variables ───────────────────────────────────────────────────────────────

DOCKER_REGISTRY ?= 911788523496.dkr.ecr.ap-south-1.amazonaws.com
IMAGE_TAG       ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")
COMPOSE_FILE    ?= docker-compose.yaml

# ─── Help ─────────────────────────────────────────────────────────────────────

help: ## Show this help message
	@echo ""
	@echo "CloudNative Commerce — Developer Makefile"
	@echo "=========================================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ─── Linting ──────────────────────────────────────────────────────────────────

lint: lint-go lint-python lint-docker lint-terraform lint-yaml ## Run all linters

lint-go: ## Lint the product-api Go service
	@echo "→ Running go vet on product-api..."
	cd services/product-api && go vet ./...
	@echo "→ Running gofmt check on product-api..."
	@test -z "$$(gofmt -l services/product-api)" || \
		(echo "✗ gofmt issues found. Run: gofmt -w services/product-api/" && exit 1)
	@echo "✓ Go lint passed"

lint-python: ## Lint the order-worker Python service (ruff)
	@echo "→ Running ruff on order-worker..."
	cd services/order-worker && ruff check . && ruff format --check .
	@echo "✓ Python lint passed"

lint-docker: ## Lint all Dockerfiles with hadolint
	@echo "→ Linting Dockerfiles..."
	@find . -name "Dockerfile" -not -path "*/node_modules/*" | while read f; do \
		echo "  checking $$f"; \
		hadolint --ignore DL3008 --ignore DL3018 "$$f"; \
	done
	@echo "✓ Dockerfile lint passed"

lint-terraform: ## Format-check all Terraform files
	@echo "→ Checking Terraform formatting..."
	@terraform fmt -check -recursive terraform/ || \
		(echo "✗ Run 'make fmt-terraform' to fix" && exit 1)
	@echo "✓ Terraform lint passed"

lint-yaml: ## Lint all YAML files
	@echo "→ Linting YAML files..."
	yamllint -c .yamllint.yaml .
	@echo "✓ YAML lint passed"

fmt-terraform: ## Auto-format all Terraform files
	terraform fmt -recursive terraform/

# ─── Testing ──────────────────────────────────────────────────────────────────

test: test-api test-worker ## Run all unit tests

test-api: ## Run product-api Go tests
	@echo "→ Running product-api tests..."
	cd services/product-api && go test ./... -v -race -timeout 60s
	@echo "✓ product-api tests passed"

test-worker: ## Run order-worker Python tests
	@echo "→ Running order-worker tests..."
	cd services/order-worker && python -m pytest tests/ -v
	@echo "✓ order-worker tests passed"

# ─── Docker Build ─────────────────────────────────────────────────────────────

build: build-api build-storefront build-worker ## Build all Docker images

build-api: ## Build the product-api Docker image
	@echo "→ Building product-api:$(IMAGE_TAG)..."
	docker build \
		--tag product-api:$(IMAGE_TAG) \
		--tag product-api:latest \
		--file services/product-api/Dockerfile \
		services/product-api/
	@echo "✓ product-api built"

build-storefront: ## Build the storefront Docker image
	@echo "→ Building storefront:$(IMAGE_TAG)..."
	docker build \
		--tag storefront:$(IMAGE_TAG) \
		--tag storefront:latest \
		--file services/storefront/Dockerfile \
		services/storefront/
	@echo "✓ storefront built"

build-worker: ## Build the order-worker Docker image
	@echo "→ Building order-worker:$(IMAGE_TAG)..."
	docker build \
		--tag order-worker:$(IMAGE_TAG) \
		--tag order-worker:latest \
		--file services/order-worker/Dockerfile \
		services/order-worker/
	@echo "✓ order-worker built"

# ─── ECR Push (used by CI — not for local dev) ───────────────────────────────

push-api: build-api ## Push product-api to ECR
	docker tag product-api:$(IMAGE_TAG) $(DOCKER_REGISTRY)/product-api:$(IMAGE_TAG)
	docker push $(DOCKER_REGISTRY)/product-api:$(IMAGE_TAG)

push-storefront: build-storefront ## Push storefront to ECR
	docker tag storefront:$(IMAGE_TAG) $(DOCKER_REGISTRY)/storefront:$(IMAGE_TAG)
	docker push $(DOCKER_REGISTRY)/storefront:$(IMAGE_TAG)

push-worker: build-worker ## Push order-worker to ECR
	docker tag order-worker:$(IMAGE_TAG) $(DOCKER_REGISTRY)/order-worker:$(IMAGE_TAG)
	docker push $(DOCKER_REGISTRY)/order-worker:$(IMAGE_TAG)

# ─── Docker Compose (local development) ──────────────────────────────────────

compose-up: ## Start all services locally (detached)
	@echo "→ Starting local stack..."
	@test -f .env || (echo "✗ .env file not found. Copy .env.example: cp .env.example .env" && exit 1)
	docker compose -f $(COMPOSE_FILE) up -d
	@echo "✓ Stack is up"
	@echo ""
	@echo "  Product API:  http://localhost:8080"
	@echo "  Storefront:   http://localhost:3000"
	@echo "  PgAdmin:      http://localhost:5050"
	@echo ""

compose-down: ## Stop all local services
	@echo "→ Stopping local stack..."
	docker compose -f $(COMPOSE_FILE) down
	@echo "✓ Stack stopped"

compose-down-volumes: ## Stop services AND delete all volumes (resets DB)
	@echo "→ Stopping stack and removing volumes..."
	docker compose -f $(COMPOSE_FILE) down -v
	@echo "✓ Stack stopped and volumes removed"

compose-logs: ## Tail logs from all services
	docker compose -f $(COMPOSE_FILE) logs -f

compose-logs-api: ## Tail product-api logs only
	docker compose -f $(COMPOSE_FILE) logs -f product-api

compose-logs-worker: ## Tail order-worker logs only
	docker compose -f $(COMPOSE_FILE) logs -f order-worker

compose-ps: ## Show status of all local containers
	docker compose -f $(COMPOSE_FILE) ps

compose-restart: ## Restart all services (useful after config changes)
	docker compose -f $(COMPOSE_FILE) restart

# ─── Pre-commit ───────────────────────────────────────────────────────────────

pre-commit-install: ## Install pre-commit hooks into .git/hooks
	@echo "→ Installing pre-commit hooks..."
	pre-commit install
	pre-commit install --hook-type commit-msg
	@echo "✓ Pre-commit hooks installed"

pre-commit-run: ## Run all pre-commit checks against all files
	@echo "→ Running pre-commit on all files..."
	pre-commit run --all-files

# ─── Cleanup ─────────────────────────────────────────────────────────────────

clean: ## Remove local build artifacts and stopped containers
	@echo "→ Cleaning up..."
	docker compose -f $(COMPOSE_FILE) down --remove-orphans 2>/dev/null || true
	docker image prune -f
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.pyc" -delete 2>/dev/null || true
	@echo "✓ Cleanup done"
