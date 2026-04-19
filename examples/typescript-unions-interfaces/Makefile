clean:
	rm -rf src/generated

generate: clean
	dart run main.dart --config config.json

install:
	npm install

run: typecheck
	npx tsx src/main.ts

typecheck:
	npx tsc --noEmit