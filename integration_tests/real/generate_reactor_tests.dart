import 'dart:io';

class _Suite {
  final String blocking;
  final String reactive;
  final String package;
  final bool wrapInRx;

  const _Suite(this.blocking, this.reactive, this.package, {this.wrapInRx = false});
}

const _suites = [
  _Suite('java_client_tests_real', 'java_client_tests_reactor_real', 'dev/graphlink/test'),
  _Suite('java_rest_client_tests_real', 'java_rest_reactor_client_tests_real', 'dev/graphlink/rest'),
  _Suite('java_client_upload_tests_real', 'java_client_upload_reactor_tests_real', 'dev/graphlink/upload'),
  _Suite('java_rest_client_tests_real', 'java_rest_rxjava3_client_tests_real', 'dev/graphlink/rest', wrapInRx: true),
  _Suite('java_rest_client_tests_real', 'java_rest_mutiny_client_tests_real', 'dev/graphlink/rest', wrapInRx: true),
];

// The reactive suite runs the same tests as the blocking one: every
// `client.queries.x(...)` / `client.mutations.x(...)` returns a Mono, so the
// tests differ only by a trailing `.block()`. RxJava and Mutiny have no common
// blocking operator (and RxJava returns Maybe/Completable), so their calls are
// wrapped in the suite's own `Rx.block(...)` instead. Files that have a
// hand-written counterpart in the reactive suite (adapters, subscriptions) are
// not derived.
void main() {
  final root = File.fromUri(Platform.script).parent.path;
  for (final suite in _suites) {
    _derive(root, suite.blocking, suite.reactive, suite.package, suite.wrapInRx);
  }
}

void _derive(String root, String blocking, String reactive, String package, bool wrapInRx) {
  final source = Directory('$root/$blocking/client-app/src/test/java/$package');
  final handWritten = _fileNames(Directory('$root/$reactive/client-app/src/test/java/$package'));
  final target = Directory('$root/$reactive/client-app/src/test/generated/java/$package');

  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);

  var count = 0;
  for (final file in source.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (!name.endsWith('.java') || handWritten.contains(name)) continue;
    File('${target.path}/$name').writeAsStringSync(_toReactive(file.readAsStringSync(), wrapInRx));
    count++;
  }
  stdout.writeln('Derived $count reactive tests into ${target.path}');
}

Set<String> _fileNames(Directory dir) => dir.existsSync()
    ? dir.listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toSet()
    : {};

final _clientCall = RegExp(r'\.(queries|mutations)\.\w+\(');

String _toReactive(String source, bool wrapInRx) {
  final out = StringBuffer();
  var position = 0;
  for (final match in _clientCall.allMatches(source)) {
    if (match.start < position) continue;
    final end = _closingParen(source, match.end - 1);
    if (wrapInRx) {
      final start = _receiverStart(source, match.start);
      out
        ..write(source.substring(position, start))
        ..write('Rx.block(')
        ..write(source.substring(start, end + 1))
        ..write(')');
    } else {
      out
        ..write(source.substring(position, end + 1))
        ..write('.block()');
    }
    position = end + 1;
  }
  out.write(source.substring(position));
  return out.toString();
}

int _receiverStart(String source, int dot) {
  final identifier = RegExp(r'[A-Za-z0-9_]');
  var start = dot;
  while (start > 0) {
    final previous = source[start - 1];
    if (identifier.hasMatch(previous)) {
      start--;
    } else if (previous == ')') {
      var depth = 0;
      do {
        start--;
        if (source[start] == ')') depth++;
        if (source[start] == '(') depth--;
      } while (depth > 0);
    } else {
      break;
    }
  }
  return start;
}

int _closingParen(String source, int open) {
  var depth = 0;
  var inString = false;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (inString) {
      if (c == r'\') {
        i++;
      } else if (c == '"') {
        inString = false;
      }
    } else if (c == '"') {
      inString = true;
    } else if (c == '(') {
      depth++;
    } else if (c == ')' && --depth == 0) {
      return i;
    }
  }
  throw StateError('Unbalanced parenthesis at offset $open');
}
