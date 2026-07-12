PORT ?= 9997

.PHONY: install generate test ci remove-generated

install:
	dart pub get

remove-generated:
	rm -rf lib/generated

generate: remove-generated
	dart run ../../generate.dart

test:
	SERVER_PORT=$(PORT) dart test -j 1

ci: install generate test
