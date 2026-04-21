clean:
	rm -rf src/generated

generate: clean
	dart run main.dart --config config.json

install:
	npm install

typecheck: generate
	npx tsc --noEmit

dev: generate
	npx tsx src/main.ts
