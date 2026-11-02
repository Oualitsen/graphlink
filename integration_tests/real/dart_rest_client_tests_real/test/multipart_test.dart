import 'dart:convert';
import 'dart:typed_data';

import 'package:graphlink_rest_real_tests/generated/graphlink.dart';
import 'support.dart';
import 'variant.dart';
import 'package:test/test.dart';

void main() {
  late GraphLinkClient client;

  setUp(() async {
    await resetServer();
    client = newClient();
  });

  group('multipart body', () {
    test('has a boundary and carries text parts without a filename', () async {
      final e = await client.mutations.eMultipart(title: 'Hello é');
      expect(e.contentType, matches(RegExp(r'^multipart/form-data; boundary=')));
      final title = e.part('title');
      expect(title.filename, isNull);
      expect(title.text, 'Hello é');
    });

    test('a file part keeps its bytes, filename and mime type', () async {
      final bytes = pattern(70000);
      final e = await client.mutations.eMultipart(one: uploadOf(bytes, filename: 'photo.png', mimeType: 'image/png'));
      final part = e.part('one');
      expect(part.filename, 'photo.png');
      expect(part.contentType, startsWith('image/png'));
      expect(part.size, bytes.length);
      expect(part.sha256, sha256Of(bytes));
    });

    test('a list of uploads repeats the part name, in order', () async {
      final files = [pattern(10), pattern(2000), Uint8List(0)];
      final e = await client.mutations.eMultipart(
        many: [for (var i = 0; i < files.length; i++) uploadOf(files[i], filename: 'f$i.bin')],
      );
      final parts = e.partsNamed('many');
      expect(parts.map((p) => p.filename), ['f0.bin', 'f1.bin', 'f2.bin']);
      expect(parts.map((p) => p.size), [10, 2000, 0]);
      expect(parts.map((p) => p.sha256), files.map(sha256Of));
    });

    test('an upload of unknown length is buffered and still arrives intact', () async {
      final bytes = pattern(300000);
      final e = await client.mutations.eMultipart(one: uploadOf(bytes, filename: 'u.bin', knownLength: false));
      expect(e.part('one').sha256, sha256Of(bytes));
    });

    test('a non-ASCII filename survives', () async {
      final e = await client.mutations.eMultipart(one: uploadOf(pattern(3), filename: 'é漢.png'));
      expect(e.part('one').filename, anyOf('é漢.png', Uri.encodeComponent('é漢.png')));
    });

    test('FLAT objects become text parts named with the configured separator', () async {
      final e = await client.mutations.eMultipart(meta: Meta(name: 'm', tags: ['a', 'b'], address: Address(city: 'Oran')));
      expect(e.part(variant.key('meta', ['name'])).text, 'm');
      expect(e.partsNamed(variant.comma ? variant.key('meta', ['tags']) : variant.key('meta', ['tags'])).map((p) => p.text),
          variant.comma ? ['a,b'] : ['a', 'b']);
      expect(e.part(variant.key('meta', ['address', 'city'])).text, 'Oran');
    });

    test('JSON encoding is a part with an application/json content type', () async {
      final e = await client.mutations.eMultipart(asJson: Meta(name: 'm'));
      final part = e.part('j');
      expect(part.contentType, startsWith('application/json'));
      expect((jsonDecode(part.text!) as Map)['name'], 'm');
    });

    test('text, file and object parts travel together', () async {
      final bytes = pattern(1000);
      final e = await client.mutations.eMultipart(
        title: 't',
        asJson: Meta(name: 'm'),
        one: uploadOf(bytes, filename: 'a.bin'),
        many: [uploadOf(bytes, filename: 'b.bin'), uploadOf(bytes, filename: 'c.bin')],
      );
      expect(e.parts.map((p) => p.name), ['title', 'j', 'one', 'many', 'many']);
    });

    test('when nothing is set there is no body and no Content-Type', () async {
      final e = await client.mutations.eMultipart();
      expect(e.bodySize, 0);
      expect(e.contentType, isNull);
    });

    test('progress reports increasing byte counts ending at the total', () async {
      final bytes = pattern(1500000);
      final reports = <List<int>>[];
      final e = await client.mutations.eMultipart(
        one: uploadOf(bytes, filename: 'big.bin'),
        onProgress: (sent, total) => reports.add([sent, total]),
      );
      expect(e.part('one').sha256, sha256Of(bytes));
      expect(reports, isNotEmpty);
      for (var i = 1; i < reports.length; i++) {
        expect(reports[i][0], greaterThanOrEqualTo(reports[i - 1][0]));
      }
      expect(reports.last[0], reports.last[1]);
      expect(reports.last[1], greaterThan(bytes.length));
    });
  });
}
