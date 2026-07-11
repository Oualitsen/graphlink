.PHONY: install generate test clean ci ci-no-generate

install:
	dart pub get

generate: install
	dart run ../generate.dart

test:
	dart test test/

clean:
	rm -rf lib/generated

ci: generate test

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate: install test
