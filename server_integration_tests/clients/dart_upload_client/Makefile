.PHONY: install generate test ci remove-generated

install:
	dart pub get

remove-generated:
	rm -rf lib/generated

generate: remove-generated
	dart run ../../generate.dart

test:
	dart test -j 1

ci: install generate test
