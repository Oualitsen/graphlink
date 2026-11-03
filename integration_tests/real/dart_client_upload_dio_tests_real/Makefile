.PHONY: install generate test clean ci ci-no-generate

install:
	dart pub get

generate: install
	dart run ../../generate.dart

test:
	dart test test/all_test.dart

clean:
	rm -rf lib/generated

ci: generate test

ci-no-generate: install test
