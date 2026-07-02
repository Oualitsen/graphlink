GENERATED_DIR = client-app/src/main/kotlin/dev/graphlink/github/generated

.PHONY: clean generate compile compile-only

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	fvm dart run ../../../lib/src/main.dart -c config.json

compile: generate
	cd client-app && ./gradlew compileKotlin

compile-only:
	cd client-app && ./gradlew compileKotlin
