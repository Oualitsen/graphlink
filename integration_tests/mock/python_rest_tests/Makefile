.PHONY: install generate generate-rest-only test clean ci ci-no-generate

PY := .venv/bin/python

.venv:
	python3 -m venv .venv

install: .venv
	$(PY) -m pip install -q -r requirements.txt

generate:
	dart run ../../generate.dart
	$(MAKE) generate-rest-only

generate-rest-only:
	cd rest_only && dart run ../../../generate.dart

test:
	$(PY) -m unittest discover -s tests -t .
	cd rest_only && ../$(PY) -m unittest discover -s tests -t .

clean:
	rm -rf generated rest_only/generated

ci: install generate test

ci-no-generate: install generate-rest-only test
