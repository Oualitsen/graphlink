.PHONY: install generate test clean ci ci-no-generate

install:
	true

generate:
	dart run ../../../generate.dart

test:
	go test -count=1 ./tests/...

clean:
	rm -rf generated

ci: generate test

ci-no-generate: install test
