CLIENT_DIR = client-app
GENERATED_DIR = client-app/src/main/java/dev/graphlink/test/generated
SERVER_JAR = ../spring_server/build/libs/graphlink-test-server-0.0.1.jar
UPLOAD_SERVER_JAR = ../spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar

.PHONY: generate test clean ci start-server stop-server start-upload-server stop-upload-server reconnect-test

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	dart pub get
	dart run lib/generate.dart

start-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) --server.port=9999 --management.server.port=9990 &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true

test:
	cd $(CLIENT_DIR) && mvn test -Dexcludes='**/SubscriptionReconnectTest.java'

start-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
	sleep 2
	java -jar $(UPLOAD_SERVER_JAR) --server.port=9998 --management.server.port=9991 &
	sleep 6

stop-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true

ci: start-server start-upload-server generate test stop-server stop-upload-server

reconnect-test: generate
	cd $(CLIENT_DIR) && SERVER_JAR=$(abspath $(SERVER_JAR)) mvn test -Dtest=SubscriptionReconnectTest
