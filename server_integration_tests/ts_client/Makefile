PORT ?= 9997

.PHONY: install generate test ci

install:
	dart pub get
	npm install

generate:
	dart run lib/generate.dart

test:
	SERVER_PORT=$(PORT) npx vitest run

ci: install generate test
