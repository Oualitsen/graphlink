.PHONY: generate test clean ci

generate:
	dart pub get
	dart run lib/generate.dart

test:
	dart test test/

clean:
	rm -rf lib/generated

ci: generate test
