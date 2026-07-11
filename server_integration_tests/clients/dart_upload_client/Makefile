.PHONY: install generate test ci

install:
	dart pub get

generate:
	dart run ../../generate.dart

test:
	dart test -j 1

ci: install generate test
