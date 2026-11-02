.PHONY: generate generate-rest-only test clean ci ci-no-generate

generate:
	rm -rf generated rest_only/generated
	dart run ../../generate.dart
	$(MAKE) generate-rest-only

generate-rest-only:
	cd rest_only && dart run ../../../generate.dart

test:
	go test -count=1 ./tests/...
	cd rest_only && go test -count=1 ./tests/...

clean:
	rm -rf generated rest_only/generated

ci: generate test

ci-no-generate: generate-rest-only test
