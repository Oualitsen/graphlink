PORT = 9996
MANAGEMENT_PORT = 9990
PID_FILE = .server.pid
FIXTURES := $(abspath ../../fixtures.json)

.PHONY: generate build start-server start-server-sync stop-server

generate:
	dart run ../../../lib/src/main.dart -c config.json

build:
	./gradlew build -x test

start-server:
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	-lsof -ti :$(MANAGEMENT_PORT) | xargs kill -9 2>/dev/null || true
	FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun > /tmp/java-server.log 2>&1 & echo $$! > $(PID_FILE)
	@echo "Waiting for java_server on port $(PORT)..."
	@until curl -s -o /dev/null http://localhost:$(PORT)/graphql; do sleep 1; done

start-server-sync:
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	-lsof -ti :$(MANAGEMENT_PORT) | xargs kill -9 2>/dev/null || true
	FIXTURES_PATH=$(FIXTURES) ./gradlew bootRun

stop-server:
	-curl -s -X POST http://localhost:$(MANAGEMENT_PORT)/actuator/shutdown 2>/dev/null || true
	-kill $$(cat $(PID_FILE) 2>/dev/null) 2>/dev/null || true
	-lsof -ti :$(PORT) | xargs kill -9 2>/dev/null || true
	-lsof -ti :$(MANAGEMENT_PORT) | xargs kill -9 2>/dev/null || true
	rm -f $(PID_FILE)

ci: generate build
