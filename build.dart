// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show File, Process, exit, stderr, stdout;
import 'package:path/path.dart' as p;
import 'package:native_assets_cli/native_assets_cli.dart';

const packageName = 'quickjs';
const _repoLibName = 'libquickjs.so';

/// Implements the protocol from `package:native_assets_cli` by building
/// the C code in `src/` and reporting what native assets it built.
void main(List<String> args) async {
  await build(args, _builder);
}

Future<void> _builder(BuildConfig buildConfig, BuildOutput buildOutput) async {
  final pkgRoot = buildConfig.packageRoot;
  final srcDir = pkgRoot.resolve('src');
  final proc = await Process.start(
    'make',
    [
      '-j',
      _repoLibName,
    ],
    workingDirectory: srcDir.path,
  );
  stdout.addStream(proc.stdout);
  stderr.addStream(proc.stderr);
  final code = await proc.exitCode;
  if (code != 0) {
    exit(code);
  }

  final linkMode = _linkMode(buildConfig.linkModePreference);
  final libName = buildConfig.targetOS.libraryFileName(packageName, linkMode);
  final libUri = buildConfig.outputDirectory.resolve(libName);
  File(p.join(srcDir.path, _repoLibName)).renameSync(libUri.path);

  buildOutput.addAsset(NativeCodeAsset(
    package: packageName,
    name: 'src/lib_$packageName.dart',
    linkMode: linkMode,
    os: buildConfig.targetOS,
    file: libUri,
    architecture: buildConfig.targetArchitecture,
  ));
  final src = [
    'src/quickjs.c',
    'src/libregexp.c',
    'src/libunicode.c',
    'src/cutils.c',
    'src/libc.c',
    'src/libbf.c',
  ];

  buildOutput.addDependencies([
    ...src.map((s) => pkgRoot.resolve(s)),
    pkgRoot.resolve('build.dart'),
  ]);
}

LinkMode _linkMode(LinkModePreference preference) {
  if (preference == LinkModePreference.dynamic ||
      preference == LinkModePreference.preferDynamic) {
    return DynamicLoadingBundled();
  }
  assert(preference == LinkModePreference.static ||
      preference == LinkModePreference.preferStatic);
  return StaticLinking();
}
