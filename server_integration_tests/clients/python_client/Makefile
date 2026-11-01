PORT ?= 9997
PY := .venv/bin/python

.PHONY: install generate test ci remove-generated

.venv:
	python3 -m venv .venv

install: .venv
	$(PY) -m pip install -q -r requirements.txt

remove-generated:
	rm -rf generated

generate: remove-generated
	dart run ../../generate.dart

test:
	SERVER_PORT=$(PORT) $(PY) -m unittest discover -s tests -t .

ci: install generate test
