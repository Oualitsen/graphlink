ERRORS_PORT = 9930

.PHONY: install generate typecheck test clean ci ci-no-generate run

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

run: generate typecheck test

ci: start-errors-server
	status=0; $(MAKE) run || status=$$?; $(MAKE) stop-errors-server; exit $$status

ci-no-generate: start-errors-server
	status=0; (npm install && $(MAKE) typecheck test) || status=$$?; $(MAKE) stop-errors-server; exit $$status

include ../errors_server/errors.mk
