PORT ?= 9997

.PHONY: install generate test ci remove-generated

install:
	go mod download

remove-generated:
	rm -rf generated

generate: remove-generated
	dart run ../../generate.dart

test:
	SERVER_PORT=$(PORT) go test -count=1 -p 1 ./tests/...

ci: install generate test
