NAME = kotlin_server_suspend
START_CMD = env FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun
PORT = 9995
MANAGEMENT_PORT = 9993
PID_FILE = .server.pid
FIXTURES := $(abspath ../../fixtures.json)

.PHONY: generate build start-server start-server-sync stop-server ci

generate: clear-generated-files
	dart run ../../generate.dart

build:
	./gradlew build -x test


start-server-sync:
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	-lsof -ti :$(MANAGEMENT_PORT) | xargs kill -9 2>/dev/null || true
	FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun


ci: generate build


clear-generated-files:
	rm -rf src/main/kotlin/dev/graphlink/kotlinserversuspend/generated/

include ../../scripts/server.mk
