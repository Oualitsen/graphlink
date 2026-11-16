NAME = python_upload_server
PY = .venv/bin/python
START_CMD = $(PY) start.py
SKIP_WS = 1
PORT = 9974
PID_FILE = .server.pid
FIXTURES := $(abspath ../../fixtures.json)

.PHONY: install generate typecheck start-server stop-server ci remove-generated

.venv:
	python3 -m venv .venv

install: .venv
	$(PY) -m pip install -q -r requirements.txt

remove-generated:
	rm -rf generated

generate: remove-generated
	dart run ../../generate.dart

typecheck:
	$(PY) -m compileall -q generated impl start.py

ci: install generate typecheck

include ../../scripts/server.mk
