import 'dart:convert';
import 'dart:io';

import 'package:graphlink/src/serializers/client_serializers/dart/dart_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/java/java_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/kotlin/kotlin_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/swift/swift_client_constants.dart';
import 'package:graphlink/src/serializers/client_serializers/typescript/typescript_client_constants.dart';
import 'package:test/test.dart';

import 'sha256_vectors.dart';

String _hexOf(String text) => utf8.encode(text).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Each program reads hex-encoded UTF-8 lines on stdin and prints `<hex>\t<digest>`.
Future<Map<String, String>> _run(
  String fileName,
  String source,
  String executable,
  List<String> Function(String file) arguments,
) async {
  final dir = Directory.systemTemp.createTempSync('glink_sha256_');
  try {
    final file = File('${dir.path}/$fileName')..writeAsStringSync(source);
    final process = await Process.start(executable, arguments(file.path), workingDirectory: dir.path);
    for (final input in sha256Vectors.keys) {
      process.stdin.writeln(_hexOf(input));
    }
    await process.stdin.close();
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    final code = await process.exitCode;
    expect(code, 0, reason: await err);
    return {
      for (final line in LineSplitter.split(await out).where((l) => l.contains('\t')))
        line.split('\t')[0]: line.split('\t')[1],
    };
  } finally {
    dir.deleteSync(recursive: true);
  }
}

void _expectAgreesWithReference(Map<String, String> actual) {
  expect(actual.length, sha256Vectors.length);
  for (final entry in sha256Vectors.entries) {
    expect(actual[_hexOf(entry.key)], entry.value, reason: 'input of ${entry.key.length} chars');
  }
}

const _slow = Timeout(Duration(minutes: 4));

void main() {
  test('dart', () async {
    const source = "import 'dart:convert';\nimport 'dart:io';\n$dartSha256\n"
        r'''
void main() {
  String? line;
  while ((line = stdin.readLineSync()) != null) {
    final bytes = <int>[];
    for (var i = 0; i < line!.length; i += 2) {
      bytes.add(int.parse(line.substring(i, i + 2), radix: 16));
    }
    print(line + '\t' + GraphLinkSha256.hex(utf8.decode(bytes)));
  }
}
''';
    _expectAgreesWithReference(await _run('main.dart', source, Platform.resolvedExecutable, (f) => [f]));
  }, timeout: _slow);

  test('java', () async {
    const source = r'''
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

class Main {
  public static void main(String[] args) throws Exception {
    BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
    String line;
    while ((line = reader.readLine()) != null) {
      byte[] bytes = new byte[line.length() / 2];
      for (int i = 0; i < bytes.length; i++) {
        bytes[i] = (byte) Integer.parseInt(line.substring(2 * i, 2 * i + 2), 16);
      }
      System.out.println(line + "\t" + GraphLinkSha256.hex(new String(bytes, StandardCharsets.UTF_8)));
    }
  }
}

''' + javaSha256;
    _expectAgreesWithReference(await _run('Main.java', source, 'java', (f) => [f]));
  }, timeout: _slow);

  test('kotlin', () async {
    const source = kotlinSha256 + r'''

generateSequence(::readLine).forEach { line ->
  val bytes = ByteArray(line.length / 2) { line.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
  println(line + "\t" + GraphLinkSha256.hex(bytes.decodeToString()))
}
''';
    _expectAgreesWithReference(await _run('main.kts', source, 'kotlinc', (f) => ['-script', f]));
  }, timeout: _slow);

  test('typescript', () async {
    const source = r'''
import { readFileSync } from 'node:fs';

''' + tsSha256 + r'''

for (const line of readFileSync(0, 'utf8').split('\n').slice(0, -1)) {
  const bytes = new Uint8Array(line.length / 2);
  for (let i = 0; i < bytes.length; i++) bytes[i] = parseInt(line.substring(i * 2, i * 2 + 2), 16);
  console.log(line + '\t' + GraphLinkSha256.hex(new TextDecoder().decode(bytes)));
}
''';
    _expectAgreesWithReference(await _run('main.ts', source, 'node', (f) => [f]));
  }, timeout: _slow);

  test('swift', () async {
    const source = swiftSha256 + r'''

while let line = readLine(strippingNewline: true) {
  var bytes = [UInt8]()
  var index = line.startIndex
  while index < line.endIndex {
    let next = line.index(index, offsetBy: 2)
    bytes.append(UInt8(line[index..<next], radix: 16)!)
    index = next
  }
  print(line + "\t" + GraphLinkSha256.hex(String(decoding: bytes, as: UTF8.self)))
}
''';
    _expectAgreesWithReference(await _run('main.swift', source, 'swift', (f) => [f]));
  }, timeout: _slow);
}
