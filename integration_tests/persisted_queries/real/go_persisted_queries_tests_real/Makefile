SERVER_JAR = ../spring_persisted_queries_server/build/libs/graphlink-persisted-queries-server-0.0.1.jar

.PHONY: install generate test clean ci ci-no-generate start-server stop-server

install:
	go mod download

generate:
	rm -rf generated
	dart run ../../../generate.dart

start-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true

test:
	go test -count=1 -p 1 ./tests/...

clean:
	rm -rf generated

ci: install start-server generate test stop-server

ci-no-generate: install start-server test stop-server
