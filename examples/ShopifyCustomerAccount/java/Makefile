GENERATED_DIR = client-app/src/main/java/dev/graphlink/shopify/customeraccount/generated

.PHONY: clean generate compile

clean:
	rm -rf $(GENERATED_DIR)

generate: clean
	fvm dart run ../../../lib/src/main.dart -c config.json

compile: generate
	cd client-app && mvn compile -q
