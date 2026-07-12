PORT ?= 9997

.PHONY: install generate test ci remove-generated

install:
	dart pub get
	npm install

remove-generated:
	rm -rf src/generated

generate: remove-generated
	dart run ../../generate.dart

# --no-file-parallelism: articleCreated has no id filter, so parallel test files
# racing createArticle mutations against the same subscription can deliver the
# wrong event. dart_client avoids this the same way via `dart test -j 1`.
test:
	SERVER_PORT=$(PORT) npx vitest run --no-file-parallelism

ci: install generate test
