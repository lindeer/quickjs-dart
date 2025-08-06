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
  final codeConfig = buildConfig.code;
  final packageName = input.packageName;
  final outputDirectory = Directory.fromUri(input.outputDirectory);
  final file = await _download(packageName, codeConfig, outputDirectory);


  final codeAsset = CodeAsset(
    package: packageName,
    name: 'src/lib_$packageName.dart',
    linkMode: DynamicLoadingBundled(),
    file: file.uri,
  );
  output.assets.code.add(codeAsset);
}

const _url = 'http://127.0.0.1:8000';

Future<HttpClientResponse> _httpGet(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);
  request.followRedirects = true;
  return await request.close();
}

Future<File> _download(String name, CodeConfig config, Directory outDir) async {
  final os = config.targetOS;
  final arch = config.targetArchitecture;
  final iOSSdk = os == OS.iOS ? config.iOS.targetSdk : null;
  final suffix = iOSSdk == null ? '' : '-$iOSSdk';
  final libName = config.targetOS.dylibFileName('$name-$os-$arch$suffix');

  final proxy = String.fromEnvironment('GITHUB_PROXY');
  final prefix = (proxy.isEmpty || proxy.endsWith('/')) ? proxy : '$proxy/';
  final uri = Uri.parse('$prefix$_url/$libName');
  stderr.writeln("Downloading '$uri' ...");
  final client = HttpClient();
  var response = await _httpGet(client, uri);
  while (response.isRedirect) {
    response.drain();
    final location = response.headers.value(HttpHeaders.locationHeader);
    stderr.writeln("Redirecting $location ...");
    if (location != null) {
      response = await _httpGet(client, uri.resolve(location));
    }
  }
  if (response.statusCode != 200) {
    throw ArgumentError('The request to $uri failed(${response.statusCode}).');
  }
  final file = File.fromUri(outDir.uri.resolve(p.basename(uri.path)));
  await file.create();
  await response.pipe(file.openWrite());
  stderr.writeln("Download done. file: $file");
  return file;
}
