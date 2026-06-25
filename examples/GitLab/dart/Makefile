.PHONY: clean pub generate analyze

clean:
	rm -rf lib/generated

pub:
	fvm dart pub get

generate: clean pub
	fvm dart run lib/generate.dart

analyze: generate
	fvm dart analyze lib/generated
