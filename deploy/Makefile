# Corobook preprod — run `make setup` for the interactive first-time setup.
# All targets are driven from this deploy/ directory. See docs/deploy-preprod.md.

# docker compose v2 (plugin) with a v1 fallback
COMPOSE := $(shell docker compose version >/dev/null 2>&1 && echo "docker compose" || echo docker-compose)

APP   := $(COMPOSE) --env-file .env.preprod -f docker-compose.preprod.yml
EDGE  := $(COMPOSE) --env-file edge/.env.edge -f edge/docker-compose.edge.yml

.DEFAULT_GOAL := help

.PHONY: help setup up down restart rebuild logs ps edge-up edge-reload edge-down destroy

help: ## Show this help
	@echo "Corobook preprod make targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-13s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "First time?  run 'make setup'."

setup: ## Interactive setup — asks the questions, writes env files, brings everything up
	@bash setup.sh

up: ## Bring up the edge (Caddy) then Corobook (needs env files; run 'make setup' first)
	@test -f edge/.env.edge    || { echo "Missing edge/.env.edge — run 'make setup'."; exit 1; }
	@test -f .env.preprod      || { echo "Missing .env.preprod — run 'make setup'.";   exit 1; }
	$(EDGE) up -d
	$(APP) up -d --build

down: ## Stop Corobook (keeps data + the edge running)
	$(APP) down

restart: ## Restart the Corobook app container
	$(APP) restart web

rebuild: ## Rebuild the image and restart Corobook (after a git pull)
	$(APP) up -d --build

logs: ## Follow Corobook app logs
	$(APP) logs -f web

ps: ## Show status of all stacks
	$(APP) ps
	$(EDGE) ps

edge-up: ## Bring up only the shared Caddy edge
	$(EDGE) up -d

edge-reload: ## Reload Caddy after editing edge/Caddyfile (add other sites)
	$(EDGE) exec caddy caddy reload --config /etc/caddy/Caddyfile

edge-down: ## Stop the shared Caddy edge (do this LAST — app stacks use its network)
	$(EDGE) down

destroy: ## DESTRUCTIVE: stop Corobook and DELETE its database volume
	@printf 'This DELETES the Corobook Postgres data. Type the hostname to confirm: '; \
	read ans; host=$$(sed -n 's/^APP_HOST=//p' .env.preprod 2>/dev/null); \
	if [ -n "$$host" ] && [ "$$ans" = "$$host" ]; then $(APP) down -v && echo "Destroyed."; \
	else echo "Mismatch — aborted."; exit 1; fi
