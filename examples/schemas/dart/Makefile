.PHONY: clean pub generate analyze analyze-only

PUB_STAMP := .dart_tool/package_config.json

clean:
	rm -rf lib/generated

pub: $(PUB_STAMP)

$(PUB_STAMP): pubspec.yaml
	fvm dart pub get

generate: clean pub
	fvm dart run lib/generate.dart

analyze: generate
	fvm dart analyze lib/generated

analyze-only:
	fvm dart analyze lib/generated
