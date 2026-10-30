import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/views/config/general.dart';
import 'package:fl_clash/views/config/routing_notice.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

class ConfigView extends StatelessWidget {
  final bool? isHarmony;

  const ConfigView({super.key, this.isHarmony});

  @override
  Widget build(BuildContext context) {
    final isHarmony = this.isHarmony ?? system.isOhos;
    return BaseScaffold(
      title: context.appLocalizations.basicConfig,
      body: generateListView([
        if (isHarmony) const HarmonyRoutingNotice(),
        ...generalItems(isHarmony: isHarmony),
      ]),
    );
  }
}
