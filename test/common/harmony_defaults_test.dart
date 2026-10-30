import 'package:fl_clash/common/harmony_defaults.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'preserves mobile preferences while keeping profile DNS authoritative',
    () {
      const old = Config(
        currentProfileId: 17,
        themeProps: ThemeProps(themeMode: ThemeMode.light),
        appSettingProps: AppSettingProps(
          locale: 'en',
          autoCheckUpdate: false,
          autoRun: true,
          developerMode: true,
          disclaimerAccepted: true,
        ),
        vpnProps: VpnProps(enable: false, dnsHijacking: true),
        networkProps: NetworkProps(appendSystemDns: true),
        patchClashConfig: PatchClashConfig(
          mixedPort: 9999,
          mode: Mode.global,
          allowLan: true,
          externalController: ExternalControllerStatus.open,
          hosts: {'test.internal': '192.168.1.2'},
        ),
        excludeSSIDs: ['Home'],
        overrideDns: true,
      );
      final result = harmonyConfigDefaults(old);
      expect(result.currentProfileId, 17);
      expect(result.appSettingProps.disclaimerAccepted, isTrue);
      expect(result.appSettingProps, old.appSettingProps);
      expect(result.themeProps, old.themeProps);
      expect(result.vpnProps, old.vpnProps);
      expect(result.networkProps, old.networkProps);
      expect(result.overrideDns, isFalse);
      expect(
        result.patchClashConfig,
        old.patchClashConfig.copyWith(findProcessMode: FindProcessMode.off),
      );
      expect(result.patchClashConfig.mode, Mode.global);
      expect(result.patchClashConfig.allowLan, isTrue);
      expect(result.excludeSSIDs, old.excludeSSIDs);
      expect(harmonyConfigDefaults(result), result);
    },
  );

  test('keeps manual node choices and refresh settings across restarts', () {
    const old = Profile(
      id: 17,
      label: 'Existing subscription',
      url: 'https://subscription.example/link',
      autoUpdate: false,
      autoUpdateDuration: Duration(days: 30),
      overwriteType: OverwriteType.script,
      scriptId: 12,
      selectedMap: {'Main': 'Node'},
    );
    final result = harmonyProfileDefaults(old);
    expect(result.id, old.id);
    expect(result.label, old.label);
    expect(result.url, old.url);
    expect(result.selectedMap, old.selectedMap);
    expect(result.autoUpdate, old.autoUpdate);
    expect(result.autoUpdateDuration, old.autoUpdateDuration);
    expect(result.overwriteType, OverwriteType.standard);
    expect(result.scriptId, isNull);
    expect(harmonyProfileDefaults(result), result);
  });
}
