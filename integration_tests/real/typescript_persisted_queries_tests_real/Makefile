SERVER_JAR = ../spring_persisted_queries_server/build/libs/graphlink-persisted-queries-server-0.0.1.jar

.PHONY: generate install typecheck test clean start-server stop-server ci ci-no-generate

generate:
	dart pub get
	dart run ../../generate.dart

install:
	npm install

typecheck:
	npx tsc --noEmit

test:
	npx vitest run

clean:
	rm -rf lib/generated

start-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true

ci: start-server generate test stop-server

ci-no-generate: start-server test stop-server
