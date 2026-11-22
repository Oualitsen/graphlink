ERRORS_PORT = 9930

.PHONY: install generate test clean ci ci-no-generate

install:
	dart pub get

generate: install
	dart run ../../generate.dart

test:
	dart test test/

clean:
	rm -rf lib/generated

ci: start-errors-server generate test stop-errors-server

ci-no-generate: start-errors-server install test stop-errors-server

include ../errors_server/errors.mk
