NAME = typescript_upload_server
START_CMD = npx tsx src/start.ts
SKIP_WS = 1
PORT = 9996
PID_FILE = .server.pid

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
	npx tsx src/start.ts


ci: install generate typecheck

include ../../scripts/server.mk
