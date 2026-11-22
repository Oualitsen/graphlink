.PHONY: generate test clean ci ci-no-generate

generate:
	rm -rf generated
	dart run ../../generate.dart

test:
	go test -count=1 ./tests/...

clean:
	rm -rf generated

ci: generate test

ci-no-generate: test
