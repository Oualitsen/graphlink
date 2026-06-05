SERVER_JAR = ../spring_server/build/libs/graphlink-test-server-0.0.1.jar
UPLOAD_SERVER_JAR = ../spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar

.PHONY: generate test clean ci start-server stop-server start-upload-server stop-upload-server reconnect-test

generate:
	dart pub get
	dart run lib/generate.dart

start-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true

start-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
	sleep 2
	java -jar $(UPLOAD_SERVER_JAR) &
	sleep 6

stop-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true

test:
	dart test test/

clean:
	rm -rf lib/generated

ci: start-server start-upload-server generate test stop-server stop-upload-server

reconnect-test: generate start-server start-upload-server
	SERVER_JAR=$(shell pwd)/$(SERVER_JAR) dart test test/subscriptions_test.dart --name "reconnect"
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
