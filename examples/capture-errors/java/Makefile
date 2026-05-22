clean:
	rm -rf client-app/src/main/java/com/example/generated

generate: clean
	dart run lib/generate.dart

build:
	cd client-app && mvn compile -q
