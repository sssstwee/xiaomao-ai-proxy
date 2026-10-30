import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'build_cache.dart';
import 'fingerprint.dart';
import 'mihomo.dart';
import 'options.dart';
import 'target.dart';
import 'util.dart';

final _log = Logger('go_builder');

class GoBuilder {
  GoBuilder({
    required this.rootDir,
    required this.config,
    required this.cache,
    required this.notice,
    this.harnessInputs = const [],
  });

  final String rootDir;
  final BuildConfig config;
  final BuildCache cache;
  final BuildNotice notice;
  final List<String> harnessInputs;

  static String _mainPackage(Target target) =>
      target.isOhos ? './ohos' : './cmd/core';

  String get _corePath => p.join(rootDir, config.coreDir);
  String get _outputPath => p.join(rootDir, config.outputDir);

  Future<BuildExecution> build(Target target) async {
    if (target.isOhos) {
      final version = prepareMihomo(corePath: _corePath);
      if (config.coreVersion != version) {
        throw StateError('OHOS core_version must match the pinned $version.');
      }
      prepareOhosModule(corePath: _corePath);
    }
    final outDir = p.join(
      _outputPath,
      target.platformDir,
      target.isOhos ? target.abi : null,
    );
    ensureDir(outDir);

    final fileName = target.isOhos
        ? 'libclash.so'
        : '${config.coreName}${target.executableExtension}';
    final outFile = p.join(outDir, fileName);

    return cache.run(
      key: '${target.platformDir}-${target.goarch}-core',
      fingerprint: () => _calculateFingerprint(target),
      primaryOutput: outFile,
      notice: notice,
      build: () async {
        final env = _buildEnvironment(target);
        _log.info('Building Go core: $target');

        // A failed build must not destroy the previous artifacts.
        final stagingDir = Directory(
          p.join(outDir, '.staging-${target.goarch}-$pid'),
        );
        final staged = p.join(stagingDir.path, fileName);
        try {
          await runCommandStream(
            'go',
            _buildArguments(target, outFile: staged),
            workingDirectory: _corePath,
            environment: env,
          );
          replaceFile(staged, outFile);
          final outputs = [outFile];
          if (target.isOhos) {
            final header = p.join(outDir, 'libclash.h');
            replaceFile(p.join(stagingDir.path, 'libclash.h'), header);
            final nativeRoot = p.join(rootDir, 'ohos', 'core');
            final nativeLibrary = p.join(
              nativeRoot,
              'libs',
              target.abi,
              fileName,
            );
            final includes = p.join(
              nativeRoot,
              'src',
              'main',
              'cpp',
              'includes',
              target.abi,
            );
            final nativeHeader = p.join(includes, 'libclash.h');
            final bridgeHeader = p.join(includes, 'bridge.h');
            copyFile(outFile, nativeLibrary);
            copyFile(header, nativeHeader);
            copyFile(p.join(_corePath, 'ohos', 'bridge.h'), bridgeHeader);
            outputs.addAll([header, nativeLibrary, nativeHeader, bridgeHeader]);
          }
          _log.info('Built: $outFile');
          return outputs;
        } finally {
          if (stagingDir.existsSync()) {
            stagingDir.deleteSync(recursive: true);
          }
        }
      },
    );
  }

  Map<String, String> _buildEnvironment(Target target) {
    final environment = {
      'GOOS': target.goos,
      'GOARCH': target.goarch,
      'CGO_ENABLED': target.isOhos ? '1' : '0',
    };
    if (target.isOhos) {
      final sdk =
          Platform.environment['OHOS_SDK_HOME'] ??
          p.join(
            Platform.environment['HOS_SDK_HOME'] ?? '',
            'default',
            'openharmony',
          );
      final compiler = p.join(
        sdk,
        'native',
        'llvm',
        'bin',
        'aarch64-unknown-linux-ohos-clang',
      );
      if (!File(compiler).existsSync()) {
        throw StateError(
          'Set OHOS_SDK_HOME to the OpenHarmony SDK with its native compiler.',
        );
      }
      environment.addAll({'CC': compiler, 'GOTOOLCHAIN': 'local'});
    }
    return environment;
  }

  // Package-level vars in mihomo copy constant.Version during init, so only the
  // linker can set it for every reader.
  static const _versionSymbol = 'github.com/metacubex/mihomo/constant.Version';

  String _ldflags() => [
    config.goLdflags,
    if (config.coreVersion.isNotEmpty)
      '-X $_versionSymbol=${config.coreVersion}',
  ].join(' ');

  List<String> _buildArguments(Target target, {String? outFile}) => [
    'build',
    if (target.isOhos) ...['-modfile=.ohos.mod', '-buildmode=c-shared'],
    '-ldflags=${_ldflags()}',
    '-tags=${config.tags}',
    if (outFile != null) ...['-o', outFile],
    _mainPackage(target),
  ];

  Future<Fingerprint> _calculateFingerprint(Target target) async {
    final env = _buildEnvironment(target);
    final builder = FingerprintBuilder(rootDir: rootDir)
      ..addValue('cache_schema', BuildCache.schemaVersion)
      ..addValue('kind', 'go-core')
      ..addValue('target', {'goos': target.goos, 'goarch': target.goarch})
      ..addValue('config', config.toFingerprintMap())
      ..addValue('environment', env)
      ..addValue('arguments', _buildArguments(target));

    final goEnvResult = runCommand(
      'go',
      [
        'env',
        '-json',
        'GOVERSION',
        'GOTOOLCHAIN',
        'GOFLAGS',
        'GOEXPERIMENT',
        'GOAMD64',
        'GOARM',
        'GO386',
        'GOMIPS',
        'GOMIPS64',
        'CGO_CFLAGS',
        'CGO_CPPFLAGS',
        'CGO_CXXFLAGS',
        'CGO_LDFLAGS',
        'GOWORK',
        'GOENV',
      ],
      workingDirectory: _corePath,
      environment: env,
    );
    final goEnv = jsonDecode((goEnvResult.stdout as String).trim());
    builder.addValue('go_env', goEnv);

    final inputs = _resolveGoInputs(env, target);
    final goWork = (goEnv as Map<String, dynamic>)['GOWORK'];
    if (goWork is String && goWork.isNotEmpty && goWork != 'off') {
      inputs.add(goWork);
      final goWorkSum = p.join(p.dirname(goWork), 'go.work.sum');
      if (File(goWorkSum).existsSync()) inputs.add(goWorkSum);
    }
    inputs.addAll(harnessInputs);
    if (target.isOhos) {
      inputs.addAll([
        p.join(_corePath, 'mihomo.lock.json'),
        p.join(_corePath, 'patches', 'openharmony.patch'),
      ]);
      final toolchainPin = p.join(
        rootDir,
        '.github',
        'harmony-pinned-shas.env',
      );
      if (File(toolchainPin).existsSync()) inputs.add(toolchainPin);
      final nativePackage = p.join(
        p.dirname(p.dirname(p.dirname(env['CC']!))),
        'oh-uni-package.json',
      );
      if (File(nativePackage).existsSync()) inputs.add(nativePackage);
    }

    builder.addFiles(inputs);
    return builder.finishWithInputs();
  }

  Set<String> _resolveGoInputs(Map<String, String> environment, Target target) {
    const template =
        r'''{{range .GoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CgoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .CXXFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .MFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .HFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .FFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SwigFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SwigCXXFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .SysoFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{range .EmbedFiles}}{{$.Dir}}/{{.}}{{"\n"}}{{end}}{{with .Module}}{{if .GoMod}}{{.GoMod}}{{"\n"}}{{end}}{{end}}''';
    final result = runCommand(
      'go',
      [
        'list',
        if (target.isOhos) '-modfile=.ohos.mod',
        '-deps',
        '-tags=${config.tags}',
        '-f',
        template,
        _mainPackage(target),
      ],
      workingDirectory: _corePath,
      environment: environment,
    );
    final corePath = p.normalize(p.absolute(_corePath));
    final inputs = <String>{};
    for (final line in (result.stdout as String).split('\n')) {
      final value = line.trim();
      if (value.isEmpty) continue;
      final filePath = p.normalize(
        p.absolute(p.isAbsolute(value) ? value : p.join(_corePath, value)),
      );
      if (!p.isWithin(corePath, filePath) && !p.equals(corePath, filePath)) {
        continue;
      }
      if (!File(filePath).existsSync()) continue;
      inputs.add(filePath);
      if (p.basename(filePath) == 'go.mod') {
        final goSum = p.join(p.dirname(filePath), 'go.sum');
        if (File(goSum).existsSync()) inputs.add(goSum);
      }
    }

    for (final name in const ['go.mod', 'go.sum']) {
      final filePath = p.join(_corePath, name);
      if (File(filePath).existsSync()) inputs.add(filePath);
    }
    return inputs;
  }
}
