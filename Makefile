# BoxBox — injectable iOS dylib for Box Box Club.
#
# Every target is a thin wrapper around ./scripts/*.sh, so the same commands work
# by hand. `make` with no arguments lists the targets.

SHELL := /bin/bash
.DEFAULT_GOAL := help

APP ?=
UDID ?=
SDK ?=
CONFIG ?=
CLEAN ?=

export UDID SDK CONFIG CLEAN

.PHONY: help all project build sim sim-logs inject run install logs doctor lint fmt check version clean

# ── Meta ─────────────────────────────────────────────────────────────────────

help: ## List the available targets
	@printf '\nBoxBox — injectable iOS dylib\n\n'
	@printf 'Usage: make <target> [VAR=value]\n\n'
	@printf 'Targets:\n'
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf '\nVariables:\n'
	@printf '  %-16s %s\n' 'APP=<path>' 'input .ipa/.app for inject, run and install'
	@printf '  %-16s %s\n' 'UDID=<udid>' 'simulator or device to target (default: booted)'
	@printf '  %-16s %s\n' 'SDK=<sdk>' 'iphoneos (default) or iphonesimulator'
	@printf '  %-16s %s\n' 'CONFIG=<cfg>' 'Release (default) or Debug'
	@printf '  %-16s %s\n' 'CLEAN=1' 'wipe the simulator container before installing'
	@printf '\nNew here? Run `make doctor` first.\n\n'

all: build

version: ## Print the tweak version
	@./scripts/version.sh

doctor: ## Check the host, toolchain, repository and input app
	./scripts/doctor.sh $(APP)

# ── Build ────────────────────────────────────────────────────────────────────

project: ## Regenerate BoxBox.xcodeproj from project.yml
	xcodegen generate --spec project.yml --project .

build: ## Build the dylib -> build/BoxBox.dylib
	./scripts/build.sh

# ── Run ──────────────────────────────────────────────────────────────────────

sim: ## Simulator loop: patch, inject, install, launch
	./scripts/sim.sh $(APP)

sim-logs: ## Show BoxBox logs from the simulator (-f to follow)
	./scripts/sim-logs.sh

logs: ## Tail the device log filtered to BoxBox
	./scripts/logs.sh

# ── Inject and install ───────────────────────────────────────────────────────

inject: ## Inject the dylib into APP -> APP-injected.ipa
	@test -n "$(APP)" || { printf 'usage: make inject APP=vendor/App.ipa\n' >&2; exit 1; }
	./scripts/inject.sh "$(APP)"

run: build ## Build, inject APP, then install it on the device
	@test -n "$(APP)" || { printf 'usage: make run APP=vendor/App.ipa\n' >&2; exit 1; }
	./scripts/inject.sh "$(APP)"
	./scripts/install.sh "$(APP:.ipa=-injected.ipa)"

install: ## Install an already-injected IPA/app on the device
	@test -n "$(APP)" || { printf 'usage: make install APP=App-injected.ipa\n' >&2; exit 1; }
	./scripts/install.sh "$(APP)"

# ── Quality ──────────────────────────────────────────────────────────────────

lint: ## Run the static checks that CI runs
	./scripts/lint.sh

fmt: ## Apply clang-format to src/
	./scripts/fmt.sh

check: lint build ## Lint, then build

# ── Housekeeping ─────────────────────────────────────────────────────────────

clean: ## Remove build output and the generated project
	rm -rf build BoxBox.xcodeproj
