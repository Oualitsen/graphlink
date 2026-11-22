.PHONY: install generate generate-server typecheck test clean ci ci-no-generate

install:
	dart pub get
	npm install

generate: install
	dart run ../../generate.dart
	$(MAKE) generate-server

generate-server:
	dart run ../../../lib/src/main.dart -c config.express.json
	dart run ../../../lib/src/main.dart -c config.nest.json

typecheck:
	npx tsc --noEmit

test:
	npx vitest run

clean:
	rm -rf lib/generated lib/generated_express lib/generated_nest

ci: generate typecheck test

# Assumes the client output exists (made by a prior `make generate-all`); the server flavors are generated here.
ci-no-generate: install generate-server typecheck test
