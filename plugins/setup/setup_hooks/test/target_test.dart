import 'package:setup_hooks/src/error.dart';
import 'package:setup_hooks/src/target.dart';
import 'package:test/test.dart';

void main() {
  group('resolve', () {
    test('finds the target for a platform and GOARCH', () {
      expect(
        Target.resolve(platform: 'linux', goarch: 'arm64'),
        Target.linuxArm64,
      );
      expect(
        Target.resolve(platform: 'macos', goarch: 'arm64'),
        Target.macosArm64,
      );
      expect(
        Target.resolve(platform: 'windows', goarch: 'amd64'),
        Target.windowsAmd64,
      );
    });

    test('rejects a GOARCH or platform without a Core', () {
      expect(
        () => Target.resolve(platform: 'linux', goarch: 'riscv64'),
        throwsA(isA<BuildException>()),
      );
      expect(
        () => Target.resolve(platform: 'ios', goarch: 'arm64'),
        throwsA(isA<BuildException>()),
      );
    });
  });

  test('only Linux and Windows ship the Helper', () {
    expect(Target.all.where((target) => target.hasHelper), [
      Target.linuxArm64,
      Target.linuxAmd64,
      Target.windowsAmd64,
      Target.windowsArm64,
    ]);
  });

  test(
    'Pura X View uses the OHOS arm64 shared-library ABI without a Helper',
    () {
      final target = Target.resolve(platform: 'ohos', goarch: 'arm64');
      expect(target, Target.ohosArm64);
      expect(target.goos, 'openharmony');
      expect(target.platformDir, 'ohos');
      expect(target.goarch, 'arm64');
      expect(target.isOhos, isTrue);
      expect(target.abi, 'arm64-v8a');
      expect(target.hasHelper, isFalse);
    },
  );

  test('names the Rust target triple for Helper platforms', () {
    expect(Target.windowsAmd64.rustTriple, 'x86_64-pc-windows-msvc');
    expect(Target.linuxArm64.rustTriple, 'aarch64-unknown-linux-gnu');
    expect(() => Target.macosArm64.rustTriple, throwsA(isA<BuildException>()));
  });
}
