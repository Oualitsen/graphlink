CLIENT_DIR = client-app
GENERATED_DIR = client-app/src/main/java/dev/graphlink/test/generated
SERVER_JAR = ../spring_persisted_queries_server/build/libs/graphlink-persisted-queries-server-0.0.1.jar

.PHONY: generate test clean ci ci-no-generate start-server stop-server

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run ../../../generate.dart

start-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true

test:
	cd $(CLIENT_DIR) && mvn test

ci: start-server generate test stop-server

ci-no-generate: start-server test stop-server
