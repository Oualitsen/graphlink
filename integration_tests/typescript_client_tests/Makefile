.PHONY: generate install typecheck test clean ci ci-no-generate

generate:
	dart pub get
	dart run ../generate.dart

install:
	npm install

typecheck:
	npx tsc --noEmit

test:
	npx vitest run

clean:
	rm -rf lib/generated

ci: generate test

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate: test
