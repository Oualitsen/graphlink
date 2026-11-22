.PHONY: install generate generate-server test clean ci ci-no-generate

PY := .venv/bin/python

.venv:
	python3 -m venv .venv

install: .venv
	$(PY) -m pip install -q -r requirements.txt

generate:
	dart run ../../generate.dart
	$(MAKE) generate-server

generate-server:
	dart run ../../../lib/src/main.dart -c config.fastapi.json
	dart run ../../../lib/src/main.dart -c config.django.json

test:
	$(PY) -m unittest discover -s tests -t .

clean:
	rm -rf generated generated_fastapi generated_django

ci: install generate test

ci-no-generate: install generate-server test
