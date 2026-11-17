# Shared recipes of the Python test servers. The including Makefile sets NAME, MODE (graphql, rest or mix), PORT and RUNNER.
PY = .venv/bin/python
FIXTURES := $(abspath ../../fixtures.json)
START_CMD = env GL_MODE=$(MODE) PORT=$(PORT) FIXTURES_PATH=$(FIXTURES) $(PY) ../python_impl/$(RUNNER)
PID_FILE = .server.pid
SKIP_WS = $(if $(filter rest,$(MODE)),1,0)
READY_PATH = $(if $(filter rest,$(MODE)),/rest/count,)

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
	$(PY) -m compileall -q generated ../python_impl

ci: install generate typecheck

include ../../scripts/server.mk
