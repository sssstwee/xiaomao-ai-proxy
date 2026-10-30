import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const harmonyPatchConfig = PatchClashConfig(
  findProcessMode: FindProcessMode.off,
  dns: Dns(nameserverPolicy: {}),
);

/// Preserve user preferences; routing and DNS remain owned by the profile.
Config harmonyConfigDefaults(Config config) => config.copyWith(
  patchClashConfig: config.patchClashConfig.copyWith(
    findProcessMode: FindProcessMode.off,
  ),
  overrideDns: false,
);

Profile harmonyProfileDefaults(Profile profile) =>
    profile.copyWith(overwriteType: OverwriteType.standard, scriptId: null);
