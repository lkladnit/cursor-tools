SHELL := /bin/bash
SYNC  := ./sync.sh

.PHONY: help setup scan register harvest deploy status

help:
	@echo ""
	@echo "  cursor-tools — bidirectional Cursor tool sync"
	@echo ""
	@echo "  make setup              one-time bootstrap (clone external repos, build binaries, set env vars)"
	@echo "  make scan               discover unregistered .cursor/ dirs under ~/dev/"
	@echo "  make scan PATH=<dir>    scan a specific directory"
	@echo "  make register           auto-register all new workspaces found by scan"
	@echo "  make harvest            harvest all namespaces from project repos"
	@echo "  make harvest NS=<ns>    harvest one namespace"
	@echo "  make deploy             deploy all namespaces to ~/.cursor/"
	@echo "  make deploy NS=<ns>     deploy one namespace"
	@echo "  make status             show namespace tool counts"
	@echo ""

setup:
	@bash ./setup.sh

scan:
ifdef PATH
	@$(SYNC) scan $(PATH)
else
	@$(SYNC) scan
endif

register:
	@$(SYNC) scan --force

harvest:
ifdef NS
	$(SYNC) harvest --ns $(NS)
else
	$(SYNC) harvest
endif

deploy:
ifdef NS
	$(SYNC) deploy --ns $(NS)
else
	$(SYNC) deploy
endif

status:
	$(SYNC) status
