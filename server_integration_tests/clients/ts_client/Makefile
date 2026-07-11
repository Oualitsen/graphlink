PORT ?= 9997

.PHONY: install generate test ci

install:
	dart pub get
	npm install

generate:
	dart run lib/generate.dart

# --no-file-parallelism: articleCreated has no id filter, so parallel test files
# racing createArticle mutations against the same subscription can deliver the
# wrong event. dart_client avoids this the same way via `dart test -j 1`.
test:
	SERVER_PORT=$(PORT) npx vitest run --no-file-parallelism

ci: install generate test
