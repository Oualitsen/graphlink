import 'dart:io';
import 'dart:isolate';

import 'package:graphlink/src/main.dart' as graphlink;

// Run with no args from server_integration_tests/ to regenerate every client
// and server in one process (no per-directory `dart run` startup cost).
// Per-directory Makefiles invoke this same file from inside their own
// directory (cwd has a config.json), which just generates that one target.
Future<void> main(List<String> args) async {
  if (File('config.json').existsSync()) {
    await graphlink.main(['--config', 'config.json']);
    return;
  }

  final dirs = [
    ...Directory('clients').listSync().whereType<Directory>(),
    ...Directory('servers').listSync().whereType<Directory>(),
  ].map((d) => d.absolute.path).toList()
    ..sort();

  for (final dirPath in dirs) {
    if (!File('$dirPath/config.json').existsSync()) continue;
    print('==> $dirPath');
    // Each dir runs in its own isolate: graphlink's generator caches
    // (lastGeneratedFiles, output hash cache) are top-level state that would
    // otherwise leak between directories in a shared process.
    await Isolate.run(() async {
      Directory.current = dirPath;
      await graphlink.main(['--config', 'config.json']);
    });
  }
}
