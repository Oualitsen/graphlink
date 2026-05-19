get:
	fvm flutter pub get

generate:
	fvm dart run lib/generate.dart

clean-widgets:
	rm -rf lib/generated/widgets

web:
	fvm flutter run -d chrome --web-port 9090

all: get generate

.PHONY: get generate clean-widgets web all
