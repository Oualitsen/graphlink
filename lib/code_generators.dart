/// GraphLink — GraphQL code generation for Dart, Flutter, Java, TypeScript,
/// and Spring Boot.
///
/// This library exposes the `build_runner` integration for Dart/Flutter
/// projects. For CLI-based generation (recommended), see the `glink` binary.
///
/// ## build_runner usage
///
/// Add to `pubspec.yaml`:
///
/// ```yaml
/// dev_dependencies:
///   graphlink: ^4.6.0
///   build_runner: ^2.4.0
/// ```
///
/// Configure `build.yaml`:
///
/// ```yaml
/// targets:
///   $default:
///     builders:
///       graphlink|graphlinkGeneratorBuilder:
///         options:
///           packageName: my_app
///           generateAllFieldsFragments: true
///           autoGenerateQueries: true
/// ```
///
/// Then run:
///
/// ```bash
/// dart run build_runner build
/// ```
///
/// ## CLI usage (recommended)
///
/// ```bash
/// # Install
/// dart pub global activate graphlink
///
/// # Generate (reads glink.json / glink.yaml / glink.yml automatically)
/// glink
///
/// # Watch mode
/// glink -w
/// ```
library graphlink;

import 'package:build/build.dart';
import 'package:graphlink/graphlink_generator_builder.dart';

/// Creates a [GraphlinkGeneratorBuilder] configured with [options] from
/// `build.yaml`.
///
/// This factory function is referenced by `build.yaml` under the
/// `graphlink|graphlinkGeneratorBuilder` builder key and is called
/// automatically by `build_runner`.
Builder graphlinkGeneratorBuilder(BuilderOptions options) =>
    GraphlinkGeneratorBuilder(options);
