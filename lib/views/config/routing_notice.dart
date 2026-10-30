import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';

class HarmonyRoutingNotice extends StatelessWidget {
  const HarmonyRoutingNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return ListItem(
      leading: const Icon(Icons.info_outline),
      title: Text(context.appLocalizations.harmonyRoutingManaged),
    );
  }
}
