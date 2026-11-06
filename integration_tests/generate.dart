import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:graphlink/src/main.dart' as graphlink;

// Run with no args from integration_tests/ to regenerate every client in one
// process (no per-directory `dart run` startup cost). Per-directory Makefiles
// invoke this same file from inside their own directory (cwd has a
// config.json), which just generates that one target.
Future<void> main(List<String> args) async {
  if (File('config.json').existsSync()) {
    _deleteOutputDir();
    await graphlink.main(['--config', 'config.json']);
    return;
  }

  final dirs = _configDirs(Directory.current, depth: 2)..sort();

  for (final dirPath in dirs) {
    print('==> $dirPath');
    // Each dir runs in its own isolate: graphlink's generator caches
    // (lastGeneratedFiles, output hash cache) are top-level state that would
    // otherwise leak between directories in a shared process.
    await Isolate.run(() async {
      Directory.current = dirPath;
      _deleteOutputDir();
      await graphlink.main(['--config', 'config.json']);
    });
  }
}

// Finds every directory holding a config.json, looking at most [depth] levels
// below [root] (so running from integration_tests/ covers mock/* and real/*,
// and running from mock/ or real/ covers just that group).
List<String> _configDirs(Directory root, {required int depth}) {
  final found = <String>[];
  for (final dir in root.listSync().whereType<Directory>()) {
    if (File('${dir.path}/config.json').existsSync()) {
      found.add(dir.absolute.path);
    } else if (depth > 1) {
      found.addAll(_configDirs(dir, depth: depth - 1));
    }
  }
  return found;
}

// The generator never removes files it stopped producing, and stale ones
// break compilation, so every run starts from an empty output directory.
void _deleteOutputDir() {
  final config = jsonDecode(File('config.json').readAsStringSync());
  final outputDir = config is Map ? config['outputDir'] : null;
  if (outputDir is! String || outputDir.isEmpty) return;
  final dir = Directory(outputDir);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
}
