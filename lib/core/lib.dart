import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/core.dart';
import 'package:fl_clash/plugins/service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'interface.dart';

class CoreLib extends CoreHandlerInterface {
  static CoreLib? _instance;

  Completer<bool> _connectedCompleter = Completer();
  final Service? _service;

  CoreLib._internal() : _service = service;

  @visibleForTesting
  CoreLib.test(Service service) : _service = service {
    _connectedCompleter.complete(true);
  }

  @override
  Future<String> preload() async {
    if (_connectedCompleter.isCompleted) {
      return 'core is connected';
    }
    final res = await _service?.init();
    if (res?.isEmpty != true) {
      return res ?? '';
    }
    _connectedCompleter.complete(true);
    final syncRes = await _service?.syncState(
      globalState.container.read(sharedStateProvider),
    );
    return syncRes ?? '';
  }

  factory CoreLib() {
    _instance ??= CoreLib._internal();
    return _instance!;
  }

  @override
  FutureOr<bool> destroy() async {
    return true;
  }

  @override
  Future<bool> shutdown(_) async {
    if (!_connectedCompleter.isCompleted) {
      return false;
    }
    _connectedCompleter = Completer();
    return _service?.shutdown() ?? true;
  }

  @override
  Future<bool> startListener() async {
    if (!await super.startListener()) {
      throw StateError('Core listener did not start');
    }
    try {
      if (await _service?.start() != true) {
        throw StateError('VPN service did not start');
      }
      return true;
    } catch (_) {
      try {
        await super.stopListener();
      } catch (_) {
        // Preserve the startup failure when best-effort rollback also fails.
      }
      rethrow;
    }
  }

  @override
  Future<bool> stopListener() async {
    try {
      if (!await super.stopListener()) {
        throw StateError('Core listener did not stop');
      }
    } finally {
      if (await _service?.stop() != true) {
        throw StateError('VPN service did not stop');
      }
    }
    return true;
  }

  @override
  Future<T?> invoke<T>({
    required ActionMethod method,
    dynamic data,
    Duration? timeout,
  }) async {
    final id = '${method.name}#${utils.id}';
    final result = await _service
        ?.invokeAction(Action(id: id, method: method, data: data))
        .withTimeout(onTimeout: () => null);
    if (result == null) {
      return null;
    }
    return parasResult<T>(result);
  }

  @override
  Completer get completer => _connectedCompleter;
}

CoreLib? get coreLib => system.isAndroid || system.isOhos ? CoreLib() : null;
