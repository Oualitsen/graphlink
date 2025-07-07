get:
	fvm flutter pub get

compile_win:
	dart compile exe lib/src/main.dart -o gqlcodegen.exe

compile:
	dart compile exe lib/src/main.dart -o gqlcodegen
	