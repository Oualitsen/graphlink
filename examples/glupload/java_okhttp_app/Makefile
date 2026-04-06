GRAPHLINK = dart run ../main.dart

generate: clean
	$(GRAPHLINK) --config config.json

clean:
	rm -rf lib/generated

.PHONY: generate clean
