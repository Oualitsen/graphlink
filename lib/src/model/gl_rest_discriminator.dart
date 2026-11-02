class GLRestDiscriminator {
  final String parent;
  final String field;
  final Map<String, String> valueByType;

  GLRestDiscriminator({required this.parent, required this.field, required this.valueByType});

  Map<String, String> get typeByValue => {for (final e in valueByType.entries) e.value: e.key};
}
