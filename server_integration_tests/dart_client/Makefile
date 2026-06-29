PORT ?= 9997

.PHONY: install generate test ci

install:
	dart pub get

generate:
	dart run lib/generate.dart

test:
	SERVER_PORT=$(PORT) dart test -j 1

ci: install generate test
