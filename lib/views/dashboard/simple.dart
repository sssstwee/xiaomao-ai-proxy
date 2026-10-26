import 'dart:async';

import 'package:fl_clash/common/harmony_remote_ui.dart';
import 'package:fl_clash/common/harmony_account.dart';
import 'package:fl_clash/providers/harmony_home_display.dart';
import 'package:fl_clash/state.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/dashboard/widgets/simple_connection.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';

class SimpleDashboardView extends ConsumerStatefulWidget {
  const SimpleDashboardView({super.key});

  @override
  ConsumerState<SimpleDashboardView> createState() =>
      _SimpleDashboardViewState();
}

class _SimpleDashboardViewState extends ConsumerState<SimpleDashboardView>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _subscription = TextEditingController();
  Timer? _homeTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  List<ConnectivityResult>? _lastConnectivity;
  bool _importingConfig = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(harmonyHomeDisplayProvider.notifier).refresh());
      ref.read(harmonySimpleProvider.notifier).bootstrap();
    });
    _homeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(ref.read(harmonyHomeDisplayProvider.notifier).refresh());
      }
    });
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (_lastConnectivity != null && listEquals(_lastConnectivity, results)) {
        return;
      }
      _lastConnectivity = results;
      ref
          .read(harmonySimpleProvider.notifier)
          .reportNetworkConnectivity(results);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _homeTimer?.cancel();
    _subscription.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_importingConfig) {
      unawaited(ref.read(harmonyHomeDisplayProvider.notifier).refresh());
      unawaited(ref.read(harmonySimpleProvider.notifier).onAppResumed());
    }
  }

  Future<void> _subscribe() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(harmonySimpleProvider.notifier)
        .subscribe(_subscription.text);
  }

  Future<void> _importConfig() async {
    if (_importingConfig) return;
    setState(() => _importingConfig = true);
    try {
      final file = await picker.pickerFile();
      if (file == null || !mounted) return;
      if (await file.length() > harmonyConfigMaxBytes) {
        throw const FormatException('Config exceeds size limit');
      }
      final bytes = await file.readBytes();
      if (!mounted) return;
      final imported = await ref
          .read(harmonySimpleProvider.notifier)
          .importConfig(bytes);
      if (mounted) {
        globalState.showNotifier(
          imported
              ? context.appLocalizations.harmonyConfigImportSuccess
              : context.appLocalizations.harmonyConfigImportFailed,
        );
      }
    } catch (_) {
      if (mounted) {
        globalState.showNotifier(
          context.appLocalizations.harmonyConfigImportFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _importingConfig = false);
    }
  }

  String? _activeNodeName() {
    final profile = ref.watch(currentProfileProvider);
    final groupName = profile?.currentGroupName;
    if (groupName == null) return null;
    final node = ref.watch(realSelectedProxyStateProvider(groupName)).proxyName;
    return node.isEmpty ? null : node;
  }

  int? _activeDelay(String? proxyName) {
    if (proxyName == null) return null;
    final groupName = ref.watch(currentProfileProvider)?.currentGroupName;
    final group = ref.watch(groupsProvider).getGroup(groupName ?? '');
    final url = group?.testUrl ?? ref.watch(appSettingProvider).testUrl;
    final groupDelay = ref.watch(
      delayDataSourceProvider.select((delays) => delays[url]?[groupName]),
    );
    return groupDelay ?? ref.watch(delayProvider(proxyName: proxyName));
  }

  ConnectionPhase _phase(HarmonySimpleState ui, bool running) {
    if ((ui.error != null || ui.issue != null) && !ui.busy && !running) {
      return ConnectionPhase.error;
    }
    if (ui.busy) {
      return ui.disconnecting
          ? ConnectionPhase.disconnecting
          : ConnectionPhase.connecting;
    }
    return running ? ConnectionPhase.connected : ConnectionPhase.disconnected;
  }

  @override
  Widget build(BuildContext context) {
    final texts = context.appLocalizations;
    final ui = ref.watch(harmonySimpleProvider);
    final session = ui.session;
    final ready = ref.watch(initProvider);
    final running = ref.watch(isStartProvider);
    final nodeName = _activeNodeName();
    final nodeDelay = _activeDelay(nodeName);
    final phase = _phase(ui, running);
    final features = ui.remoteRuntime['features'] as Map? ?? {};
    final refreshMessages = {
      'debounced': remoteHarmonyText(
        ref,
        'harmonyConfigRefreshDebounced',
        texts.harmonyConfigRefreshDebounced,
      ),
      'success': remoteHarmonyText(
        ref,
        'harmonyConfigRefreshSuccess',
        texts.harmonyConfigRefreshSuccess,
      ),
      'failed': remoteHarmonyText(
        ref,
        'harmonyConfigRefreshFailed',
        texts.harmonyConfigRefreshFailed,
      ),
    };

    return CommonScaffold(
      title: remoteHarmonyText(ref, 'homeTitle', appDisplayName),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: session != null
              ? SimpleConnectionPanel(
                  phase: phase,
                  username:
                      ref
                          .read(harmonyAccountApiProvider)
                          .subscriptionUri
                          ?.host ??
                      session.username,
                  directSubscription: true,
                  error: ui.error,
                  usingCachedConfig: ui.usingCachedConfig,
                  nodeName: nodeName,
                  nodeDelayMs: nodeDelay,
                  homeStatus: ui.homeStatus,
                  issue: ui.issue,
                  onToggle: ready && !ui.bootstrapping
                      ? () => ref
                            .read(harmonySimpleProvider.notifier)
                            .toggleConnect()
                      : null,
                  onLogout: () {
                    _subscription.text =
                        ref
                            .read(harmonyAccountApiProvider)
                            .subscriptionUri
                            ?.toString() ??
                        '';
                    unawaited(
                      ref.read(harmonySimpleProvider.notifier).logout(),
                    );
                  },
                  onRetry: () =>
                      ref.read(harmonySimpleProvider.notifier).retryConnect(),
                  onImportConfig:
                      ready &&
                          !ui.busy &&
                          !ui.bootstrapping &&
                          !ui.homeStatus.configSyncInProgress &&
                          !_importingConfig
                      ? _importConfig
                      : null,
                  configFreshness: ui.homeStatus.configFreshness,
                  onConfigRefresh: features['manualRefresh'] == false
                      ? null
                      : () {
                          unawaited(
                            ref
                                .read(harmonyHomeDisplayProvider.notifier)
                                .refresh(force: true),
                          );
                          unawaited(
                            ref
                                .read(harmonySimpleProvider.notifier)
                                .forceRefreshConfig(messages: refreshMessages),
                          );
                        },
                )
              : AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(24),
                      children: [
                        SvgPicture.asset(
                          'assets/images/cc_guardian.svg',
                          width: 64,
                          height: 64,
                          excludeFromSemantics: true,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          remoteHarmonyText(
                            ref,
                            'harmonySubscription',
                            texts.harmonySubscription,
                          ),
                          textAlign: TextAlign.center,
                          style: context.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          remoteHarmonyText(
                            ref,
                            'harmonySubscriptionHint',
                            texts.harmonySubscriptionHint,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _subscription,
                          enabled: !ui.busy && !ui.bootstrapping,
                          autofillHints: const [],
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          decoration: InputDecoration(
                            labelText: remoteHarmonyText(
                              ref,
                              'harmonySubscriptionUrl',
                              texts.harmonySubscriptionUrl,
                            ),
                          ),
                          validator: (value) =>
                              HarmonyAccountApi.parseSubscriptionUrl(
                                    value ?? '',
                                  ) !=
                                  null
                              ? null
                              : remoteHarmonyText(
                                  ref,
                                  'harmonySubscriptionInvalid',
                                  texts.harmonySubscriptionInvalid,
                                ),
                          onFieldSubmitted: (_) => _subscribe(),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(56),
                          ),
                          onPressed: ui.busy || ui.bootstrapping || !ready
                              ? null
                              : _subscribe,
                          child: ui.busy || ui.bootstrapping
                              ? const SizedBox.square(
                                  dimension: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  remoteHarmonyText(
                                    ref,
                                    'harmonyUseSubscription',
                                    texts.harmonyUseSubscription,
                                  ),
                                ),
                        ),
                        if (ui.error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            remoteHarmonyError(ref, texts, ui.error!),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.colorScheme.error),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
