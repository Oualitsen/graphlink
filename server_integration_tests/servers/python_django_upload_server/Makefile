NAME = python_django_upload_server
PY = .venv/bin/python
START_CMD = $(PY) start.py
SKIP_WS = 1
PORT = 9971
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
	$(PY) -m compileall -q generated ../python_impl/impl start.py settings.py services.py urls.py

ci: install generate typecheck

include ../../scripts/server.mk
