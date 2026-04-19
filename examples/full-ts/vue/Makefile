clean:
	rm -rf src/generated

generate: clean
	dart run main.dart --config config.json

install:
	npm install

start: generate install
	npm run dev

typecheck:
	npx vue-tsc --noEmit
