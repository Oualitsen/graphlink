import 'package:graphlink/src/config.dart';

class FlutterApi {
  final FlutterConfig _config;

  const FlutterApi(this._config);

  String get materialImport => _config.designLibrary == FlutterDesignLibrary.standalone
      ? 'package:material_ui/material_ui.dart'
      : 'package:flutter/material.dart';

  String get cupertinoImport => _config.designLibrary == FlutterDesignLibrary.standalone
      ? 'package:cupertino_ui/cupertino_ui.dart'
      : 'package:flutter/cupertino.dart';

  bool get useRadioGroup => _sdkAtLeast(3, 35);

  bool get useDropdownInitialValue => _sdkAtLeast(3, 35);

  String get dropdownValueParam => useDropdownInitialValue ? 'initialValue' : 'value';

  bool _sdkAtLeast(int major, int minor) {
    final version = _config.sdkVersion;
    if (version == null) return false;
    final parts = version.split('.').map(int.parse).toList();
    return parts[0] > major || (parts[0] == major && parts[1] >= minor);
  }
}
