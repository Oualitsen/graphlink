SERVER_JAR = ../spring_server/build/libs/graphlink-test-server-0.0.1.jar
UPLOAD_SERVER_JAR = ../spring_upload_server/build/libs/graphlink-upload-server-0.0.1.jar
PY := .venv/bin/python

.PHONY: install generate test clean ci ci-no-generate start-server stop-server start-upload-server stop-upload-server reconnect-test

.venv:
	python3 -m venv .venv

install: .venv
	$(PY) -m pip install -q -r requirements.txt

generate:
	dart run ../../generate.dart

start-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) --server.port=9999 --management.server.port=9990 &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9990/actuator/shutdown || true

start-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
	sleep 2
	java -jar $(UPLOAD_SERVER_JAR) --server.port=9998 --management.server.port=9991 &
	sleep 6

stop-upload-server:
	curl -s -X POST http://localhost:9991/actuator/shutdown || true

test:
	$(PY) -m unittest discover -s tests -t .

clean:
	rm -rf generated

ci: install start-server start-upload-server generate test stop-server stop-upload-server

ci-no-generate: install start-server start-upload-server test stop-server stop-upload-server

reconnect-test: install generate start-server start-upload-server
	SERVER_JAR=$(shell pwd)/$(SERVER_JAR) $(PY) -m unittest tests.test_subscription_reconnect
	curl -s -X POST http://localhost:9990/actuator/shutdown || true
	curl -s -X POST http://localhost:9991/actuator/shutdown || true
