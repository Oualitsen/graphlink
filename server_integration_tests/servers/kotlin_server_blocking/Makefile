NAME = kotlin_server_blocking
START_CMD = env FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun
PORT = 9994
MANAGEMENT_PORT = 9992
PID_FILE = .server.pid
FIXTURES := $(abspath ../../fixtures.json)

.PHONY: generate build start-server start-server-sync stop-server ci

generate: remove-generated
	dart run ../../generate.dart

build:
	./gradlew build -x test


start-server-sync:
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	-lsof -ti :$(MANAGEMENT_PORT) | xargs kill -9 2>/dev/null || true
	FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun


ci: generate build

remove-generated:
	rm -rf src/main/kotlin/dev/graphlink/kotlinserverblocking/generated/

include ../../scripts/server.mk
