// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

/// Implements the protocol from `package:native_assets_cli` by building
/// the C code in `src/` and reporting what native assets it built.
void main(List<String> args) async {
  await build(args, _builder);
}

Future<void> _builder(BuildInput input, BuildOutputBuilder output) async {
  final buildConfig = input.config;
  final pkgRoot = input.packageRoot;
  final srcDir = pkgRoot.resolve('src');
  final packageName = input.packageName;
  final libName = buildConfig.code.targetOS.dylibFileName(packageName);
  final proc = await Process.start(
    'make',
    [
      '-j',
      libName,
    ],
    workingDirectory: srcDir.path,
  );
  stdout.addStream(proc.stdout);
  stderr.addStream(proc.stderr);
  final code = await proc.exitCode;
  if (code != 0) {
    exit(code);
  }

  final libUri = input.outputDirectory.resolve(libName);
  File(p.join(srcDir.path, libName)).renameSync(libUri.path);

  final codeAsset = CodeAsset(
    package: packageName,
    name: 'src/lib_$packageName.dart',
    linkMode: DynamicLoadingBundled(),
    file: libUri,
  );
  output.assets.code.add(codeAsset);
  final src = [
    'src/quickjs.c',
    'src/libregexp.c',
    'src/libunicode.c',
    'src/cutils.c',
    'src/libc.c',
    'src/libbf.c',
  ];

  output.addDependencies([
    ...src.map((s) => pkgRoot.resolve(s)),
    pkgRoot.resolve('build.dart'),
  ]);
}
