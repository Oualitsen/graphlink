.PHONY: build watch clean get delete-generated

get:
	fvm dart pub get

build: get
	fvm dart run build_runner build --delete-conflicting-outputs

watch: get
	fvm dart run build_runner watch --delete-conflicting-outputs

clean:
	fvm dart run build_runner clean

delete-generated:
	rm -rf lib/generated
