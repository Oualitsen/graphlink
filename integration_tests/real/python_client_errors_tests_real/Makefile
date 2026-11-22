ERRORS_PORT = 9930
PY := .venv/bin/python

.PHONY: install generate test clean ci ci-no-generate run

.venv:
	python3 -m venv .venv

install: .venv
	$(PY) -m pip install -q -r requirements.txt

generate:
	dart pub get 2>/dev/null || true
	dart run ../../generate.dart

test:
	$(PY) -m unittest discover -s tests -t .

clean:
	rm -rf generated

run: install generate test

ci: start-errors-server
	status=0; $(MAKE) run || status=$$?; $(MAKE) stop-errors-server; exit $$status

ci-no-generate: start-errors-server
	status=0; ($(MAKE) install && $(MAKE) test) || status=$$?; $(MAKE) stop-errors-server; exit $$status

include ../errors_server/errors.mk
