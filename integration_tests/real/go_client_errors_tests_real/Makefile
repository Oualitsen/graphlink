ERRORS_PORT = 9930

.PHONY: generate test clean ci ci-no-generate run

generate:
	rm -rf generated
	dart pub get 2>/dev/null || true
	dart run ../../generate.dart

clean:
	rm -rf generated

test:
	go test -count=1 -p 1 ./tests/...

run: generate test

ci: start-errors-server
	status=0; $(MAKE) run || status=$$?; $(MAKE) stop-errors-server; exit $$status

ci-no-generate: start-errors-server
	status=0; $(MAKE) test || status=$$?; $(MAKE) stop-errors-server; exit $$status

include ../errors_server/errors.mk
