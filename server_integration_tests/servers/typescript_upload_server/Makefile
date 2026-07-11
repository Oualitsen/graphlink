PORT = 9996
PID_FILE = .server.pid

.PHONY: install generate typecheck start-server start-server-sync stop-server ci

install:
	npm install

generate:
	dart run ../../generate.dart

typecheck:
	npx tsc --noEmit

start-server:
	lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	npx tsx src/start.ts > /tmp/ts-upload-server-$(PORT).log 2>&1 & echo $$! > $(PID_FILE)
	sleep 2

start-server-sync:
	lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	npx tsx src/start.ts

stop-server:
	-kill $$(cat $(PID_FILE) 2>/dev/null) 2>/dev/null || true
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	rm -f $(PID_FILE)

ci: install generate typecheck
