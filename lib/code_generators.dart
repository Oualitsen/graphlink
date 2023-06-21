library code_generators;

import 'package:build/build.dart';
import 'package:parser/src/aggregation_builder.dart';


Builder aggregatingBuilder(BuilderOptions options) => AggregatingBuilder(options);
