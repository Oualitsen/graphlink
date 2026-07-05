
class GLCollectionImports {
  final String? listImport;
  final String? mapImport;

  const GLCollectionImports({this.listImport, this.mapImport});

  static const none = GLCollectionImports();

  bool get isEmpty => listImport == null && mapImport == null;
}
