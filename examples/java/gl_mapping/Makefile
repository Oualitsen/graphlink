clean:
	rm -rf app/src/main/java/com/example/generated

generate: clean
	dart run lib/generate.dart

build:
	cd app && mvn compile -q
