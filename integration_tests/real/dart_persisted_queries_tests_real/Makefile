SERVER_JAR = ../spring_persisted_queries_server/build/libs/graphlink-persisted-queries-server-0.0.1.jar

.PHONY: install generate test clean ci ci-no-generate start-server stop-server

install:
	dart pub get

generate: install
	dart run ../../generate.dart

start-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true

test:
	dart test test/

clean:
	rm -rf lib/generated

ci: start-server generate test stop-server

ci-no-generate: start-server install test stop-server
