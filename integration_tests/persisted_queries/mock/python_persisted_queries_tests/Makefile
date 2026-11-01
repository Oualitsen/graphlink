.PHONY: install generate test clean ci ci-no-generate

PY := .venv/bin/python

.venv:
	python3 -m venv .venv

install: .venv
	$(PY) -m pip install -q -r requirements.txt

generate:
	dart run ../../../generate.dart

test:
	$(PY) -m unittest discover -s tests -t .

clean:
	rm -rf generated

ci: install generate test

ci-no-generate: install test
