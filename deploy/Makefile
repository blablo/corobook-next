# Corobook production — run `make setup` for the interactive first-time setup.
# All targets are driven from this deploy/ directory. See docs/deploy-prod.md.
#
# This manages the COROBOOK APP STACK only (web + postgres + worker). The shared
# Caddy reverse proxy that fronts this and other sites lives in a SEPARATE infra
# repo and owns the external `edge` Docker network. Bring that edge up first; this
# stack just joins its network.

# docker compose v2 (plugin) with a v1 fallback
COMPOSE := $(shell docker compose version >/dev/null 2>&1 && echo "docker compose" || echo docker-compose)

APP := $(COMPOSE) --env-file .env.prod -f docker-compose.prod.yml

.DEFAULT_GOAL := help

.PHONY: help setup up down restart rebuild logs ps destroy

help: ## Show this help
	@echo "Corobook production make targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[1m%-13s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "First time?  run 'make setup'  (the shared Caddy edge must already be running)."

setup: ## Interactive setup — asks the questions, writes .env.prod, brings Corobook up
	@bash setup.sh

up: ## Bring up Corobook (needs .env.prod + the external 'edge' network; run 'make setup' first)
	@test -f .env.prod || { echo "Missing .env.prod — run 'make setup'."; exit 1; }
	@docker network inspect edge >/dev/null 2>&1 || { echo "The external 'edge' network is missing — start the shared Caddy edge first."; exit 1; }
	$(APP) up -d --build

down: ## Stop Corobook (keeps its data volume)
	$(APP) down

restart: ## Restart the Corobook app container
	$(APP) restart web

rebuild: ## Rebuild the image and restart Corobook (after a git pull)
	$(APP) up -d --build

logs: ## Follow Corobook app logs
	$(APP) logs -f web

ps: ## Show status of the Corobook stack
	$(APP) ps

destroy: ## DESTRUCTIVE: stop Corobook and DELETE its database volume
	@printf 'This DELETES the Corobook Postgres data. Type the hostname to confirm: '; \
	read ans; host=$$(sed -n 's/^APP_HOST=//p' .env.prod 2>/dev/null); \
	if [ -n "$$host" ] && [ "$$ans" = "$$host" ]; then $(APP) down -v && echo "Destroyed."; \
	else echo "Mismatch — aborted."; exit 1; fi
