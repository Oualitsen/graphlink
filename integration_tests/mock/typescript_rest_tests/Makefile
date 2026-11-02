.PHONY: install generate typecheck test clean ci ci-no-generate

install:
	dart pub get
	npm install

generate: install
	dart run ../../generate.dart

typecheck:
	npx tsc --noEmit

test:
	npx vitest run

clean:
	rm -rf lib/generated

ci: generate typecheck test

# Assumes code has already been generated (e.g. by a prior `make generate-all` job).
ci-no-generate: install typecheck test
