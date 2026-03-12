get:
	fvm flutter pub get

compile_win:
	dart compile exe lib/src/main.dart -o glink.exe

compile:
	dart compile exe lib/src/main.dart -o glink
	