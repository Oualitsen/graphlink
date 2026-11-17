NAME = nestjs_server
START_CMD = env FIXTURES_PATH=$(FIXTURES) npx tsx src/start.ts
PORT = 9926
PID_FILE = .server.pid
FIXTURES := $(abspath ../../fixtures.json)

.PHONY: install generate typecheck start-server start-server-sync stop-server ci remove-generated

install:
	npm install

remove-generated:
	rm -rf src/generated

generate: remove-generated
	dart run ../../generate.dart

typecheck:
	npx tsc --noEmit


start-server-sync:
	lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	FIXTURES_PATH=$(FIXTURES) npx tsx src/start.ts


ci: install generate typecheck

include ../../scripts/server.mk
