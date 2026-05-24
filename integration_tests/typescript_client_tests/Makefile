.PHONY: generate install typecheck test clean ci

generate:
	dart pub get
	dart run lib/generate.dart

install:
	npm install

typecheck:
	npx tsc --noEmit

test:
	npx vitest run

clean:
	rm -rf lib/generated

ci: generate test
