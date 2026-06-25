.PHONY: generate install typecheck test clean start-server stop-server start-upload-server stop-upload-server ci

SERVER_JAR = ../spring_server/build/libs/graphlink-test-server-0.0.1.jar
UPLOAD_SERVER_JAR = ../spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar

generate:
	dart pub get
	dart run lib/generate.dart

install:
	npm install

typecheck:
	npx tsc --noEmit

test:
	npx vitest run

clean:
	rm -rf lib/generated

start-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	lsof -ti :9988 | xargs kill -9 2>/dev/null || true
	sleep 1
	java -jar $(SERVER_JAR) --server.port=9988 --management.server.port=9990 &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	lsof -ti :9988 | xargs kill -9 2>/dev/null || true

start-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
	lsof -ti :9998 | xargs kill -9 2>/dev/null || true
	sleep 1
	java -jar $(UPLOAD_SERVER_JAR) --server.port=9998 --management.server.port=9991 &
	sleep 6

stop-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
	lsof -ti :9998 | xargs kill -9 2>/dev/null || true

ci: start-server start-upload-server generate test stop-server stop-upload-server

reconnect-test: generate start-server
	RUN_RECONNECT_TESTS=1 npx vitest run test/subscription-reconnect.test.ts
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
