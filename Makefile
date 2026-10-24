ROOT := $(shell pwd)
APP  ?=

.PHONY: all project build inject run install logs clean

all: build

## Regenerate BoxBox.xcodeproj from project.yml
project:
	xcodegen generate --spec project.yml --project .
build:
	./scripts/build.sh

## Inject into a target:  make inject APP=Foo.ipa
inject:
	@test -n "$(APP)" || { echo "usage: make inject APP=Foo.ipa"; exit 1; }
	./scripts/inject.sh "$(APP)"

## Build → inject → install:  make run APP=Foo.ipa
run:
	@test -n "$(APP)" || { echo "usage: make run APP=Foo.ipa"; exit 1; }
	$(MAKE) --no-print-directory inject APP="$(APP)"
	./scripts/install.sh "$(APP:.ipa=-injected.ipa)"

install:
	@test -n "$(APP)" || { echo "usage: make install APP=Foo-injected.ipa"; exit 1; }
	./scripts/install.sh "$(APP)"

logs:
	./scripts/logs.sh

clean:
	rm -rf build BoxBox.xcodeproj
