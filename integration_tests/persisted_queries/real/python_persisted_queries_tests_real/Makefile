SERVER_JAR = ../spring_persisted_queries_server/build/libs/graphlink-persisted-queries-server-0.0.1.jar
PY := .venv/bin/python

.PHONY: install generate test clean ci ci-no-generate start-server stop-server

.venv:
	python3 -m venv .venv

install: .venv
	$(PY) -m pip install -q -r requirements.txt

generate:
	dart run ../../../generate.dart

start-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true
	sleep 2
	java -jar $(SERVER_JAR) &
	sleep 6

stop-server:
	curl -s -X POST http://localhost:9992/actuator/shutdown || true

test:
	$(PY) -m unittest discover -s tests -t .

clean:
	rm -rf generated

ci: install start-server generate test stop-server

ci-no-generate: install start-server test stop-server
