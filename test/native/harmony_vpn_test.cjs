// Executes the production ArkTS lifecycle with SDK fakes; no app build or device is needed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const repo = path.resolve(__dirname, '../..');
const etsRoot = path.join(repo, 'ohos/entry/src/main/ets');
const sdkInputs = [
  process.env.OHOS_SDK_HOME,
  process.env.HOS_SDK_HOME,
  process.env.DEVECO_SDK_HOME,
  path.join(os.homedir(), '.local/share/harmony-cli/command-line-tools/sdk/default/openharmony'),
].filter(Boolean);
const sdkRoots = sdkInputs.flatMap((root) => [root, path.join(root, 'default/openharmony'), path.join(root, 'openharmony')]);
const compilerPaths = [
  process.env.TYPESCRIPT_PATH,
  'typescript',
  ...sdkRoots.map((root) => path.join(root, 'ets/build-tools/ets-loader/node_modules/typescript')),
].filter(Boolean);
let ts;
for (const candidate of compilerPaths) {
  try { ts = require(candidate); break; } catch (_) {}
}
if (!ts) throw new Error('Set TYPESCRIPT_PATH to the HarmonyOS SDK TypeScript package.');

const deferred = () => {
  let resolve;
  let reject;
  const promise = new Promise((a, b) => { resolve = a; reject = b; });
  return { promise, resolve, reject };
};
const tick = () => new Promise((resolve) => setImmediate(resolve));

function fixture(overrides = {}) {
  const calls = { create: [], destroy: 0, startTun: 0, stopTun: 0, dns: [], events: [], nets: [], subscribers: [], probes: [], backgroundStart: 0, backgroundStop: 0, networkReset: 0, notificationPublish: 0, channels: new Map() };
  const vpn = {
    create: (config) => { calls.create.push(config); return overrides.create?.(config) ?? Promise.resolve(42); },
    destroy: () => { calls.destroy++; return overrides.destroy?.() ?? Promise.resolve(); },
    protect: (fd) => overrides.protect?.(fd) ?? Promise.resolve(),
  };
  class MessageSequence {
    values = [];
    static create() { return new MessageSequence(); }
    writeLong(value) { this.values.push(value); }
    writeString(value) { this.values.push(value); }
    reclaim() {}
  }
  class ResultStub {
    constructor(name, onResult) { this.onResult = onResult; }
  }
  const globalState = { state: {}, runTime: 0, runState: 2 };
  const mocks = {
    '@kit.NetworkKit': {
      VpnExtensionAbility: class { context = { applicationInfo: { name: 'com.xiaomao.proxy' } }; },
      vpnExtension: { createVpnConnection: () => vpn },
      connection: {
        getConnectOwnerUidSync: () => { if (overrides.ownerError) throw new Error('Socket closed'); return 100; },
        createNetConnection: () => {
          const net = {
            handlers: {},
            unregisterCount: 0,
            on(event, callback) { this.handlers[event] = callback; },
            register(callback) { callback(overrides.registerError); },
            unregister(callback) { this.unregisterCount++; callback(); },
          };
          calls.nets.push(net);
          return net;
        },
      },
    },
    '@kit.AbilityKit': {
      bundleManager: { getBundleNameByUidSync: () => 'com.example.app' },
      wantAgent: {
        OperationType: { START_ABILITY: 0 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 0 },
        getWantAgent: () => overrides.wantAgent?.() ?? Promise.resolve({}),
      },
    },
    '@kit.BackgroundTasksKit': {
      backgroundTaskManager: {
        BackgroundMode: { TASK_KEEPING: 0 },
        on: (event, callback) => { calls.backgroundCancel = callback; },
        off: () => { calls.backgroundCancel = undefined; },
        startBackgroundRunning: () => { calls.backgroundStart++; return overrides.backgroundStart?.() ?? Promise.resolve(); },
        stopBackgroundRunning: () => { calls.backgroundStop++; return Promise.resolve(); },
      },
    },
    '@kit.NotificationKit': { notificationManager: {
      cancel: (id, callback) => callback(),
      publish: (request, callback) => { calls.notificationPublish++; callback(); },
      ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0 },
    } },
    '@kit.IPCKit': { rpc: { RemoteObject: class {}, MessageOption: class { setAsync() {} }, MessageSequence } },
    '@kit.BasicServicesKit': {
      deviceInfo: { sdkApiVersion: 26 },
      commonEventManager: {
        Support: { COMMON_EVENT_DEVICE_IDLE_MODE_CHANGED: 'idle', COMMON_EVENT_SCREEN_ON: 'screen-on' },
        createSubscriberSync: (options) => { const subscriber = { options }; calls.subscribers.push(subscriber); return subscriber; },
        subscribeToEvent: (subscriber, callback) => { subscriber.callback = callback; return overrides.subscribe?.() ?? Promise.resolve(); },
        unsubscribe: (subscriber, callback) => { subscriber.unsubscribeCount = (subscriber.unsubscribeCount ?? 0) + 1; callback?.(); },
        publish: (event, options, callback) => { calls.events.push({ event, data: options.data }); callback(); },
      },
    },
    '@ohos.app.ability.AbilityConstant': { default: { MemoryLevel: { MEMORY_LEVEL_CRITICAL: 4 } } },
    '@ohos/flutter_ohos': { MethodChannel: class {
      constructor(messenger, name) { this.messages = []; calls.channels.set(name, this); }
      setMethodCallHandler(handler) { this.handler = handler; }
      invokeMethod(method, args) { this.messages.push({ method, args }); return Promise.resolve(); }
    }, FlutterAbility: class {} },
    '@kit.ArkTS': { util: {
      TextEncoder: { create: () => ({ encodeInto: (value) => new TextEncoder().encode(value) }) },
      TextDecoder: { create: () => ({ decodeToString: (value) => new TextDecoder().decode(value) }) },
    } },
    core: {
      startTUN: (...args) => { calls.startTun++; calls.protect = args[0]; calls.startTunArgs = args; return overrides.startTun ?? true; },
      stopTun: () => { calls.stopTun++; return overrides.stopTun?.(); },
      suspend() {}, updateDns: (value) => calls.dns.push(value),
      setEventListener() {},
      invokeMethod: (callback, data) => {
        calls.probes.push(JSON.parse(data));
        if (overrides.probe) overrides.probe(callback);
        else callback(JSON.stringify({ result: { 'status-code': 204 } }));
      },
      quickSetup() {}, forceGC() {}, resetNetwork: () => calls.networkReset++,
    },
  };
  const fileMocks = new Map([
    [path.join(etsRoot, 'utils/Rpc.ets'), { ChunkedSender: class {}, ChunkedReader: class {} }],
    [path.join(etsRoot, 'entryability/EntryAbility.ets'), { ResultStub, CallbackStub: ResultStub }],
    [path.join(etsRoot, 'GlobalState.ets'), { globalState, RunState: { start: 0, pending: 1, stop: 2 } }],
  ]);
  if (overrides.realRpc) fileMocks.delete(path.join(etsRoot, 'utils/Rpc.ets'));
  const modules = new Map();
  const storage = new Map();
  const timers = new Map();
  let nextTimer = 0;
  function load(filename) {
    if (fileMocks.has(filename)) return fileMocks.get(filename);
    if (modules.has(filename)) return modules.get(filename).exports;
    const module = { exports: {} };
    modules.set(filename, module);
    const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
      fileName: filename,
      reportDiagnostics: true,
    });
    const errors = (result.diagnostics ?? []).filter((d) => d.category === ts.DiagnosticCategory.Error);
    assert.equal(errors.length, 0, `${filename}: ${errors.map((d) => ts.flattenDiagnosticMessageText(d.messageText, '\n')).join('\n')}`);
    const requireFile = (specifier) => {
      if (Object.hasOwn(mocks, specifier)) return mocks[specifier];
      if (specifier.startsWith('.')) return load(path.resolve(path.dirname(filename), specifier) + '.ets');
      throw new Error(`Unexpected native dependency: ${specifier}`);
    };
    const evaluate = vm.runInNewContext(`(function(require, module, exports) { ${result.outputText}\n})`, {
      console, Date, Map, Set, Promise,
      setTimeout: overrides.fakeTimers ? (callback) => { const id = ++nextTimer; timers.set(id, callback); return id; } : setTimeout,
      clearTimeout: overrides.fakeTimers ? (id) => timers.delete(id) : clearTimeout,
      AppStorage: { has: (key) => storage.has(key), get: (key) => storage.get(key), setOrCreate: (key, value) => storage.set(key, value) },
    });
    evaluate(requireFile, module, module.exports);
    return module.exports;
  }
  const VpnAbility = load(path.join(etsRoot, 'extensionAbility/VpnExtAbility.ets')).default;
  const ability = new VpnAbility();
  ability.onCreate({});
  function remote() {
    const results = [];
    return { results, sendMessageRequest: (code, send) => { results.push([...send.values]); return Promise.resolve(); } };
  }
  const options = load(path.join(etsRoot, 'models/State.ets')).VpnOptions;
  const vpnOptions = () => Object.assign(new options(), { enable: true });
  return { ability, calls, vpnOptions, remote, load, globalState, timers };
}

test('start waits for VPN creation and reports a valid NetworkKit MTU', async () => {
  const creation = deferred();
  const f = fixture({ create: () => creation.promise });
  const remote = f.remote();
  f.ability.handleStartService(f.vpnOptions(), 1234, remote);
  await tick();
  assert.equal(remote.results.length, 0);
  assert.equal(f.calls.create[0].mtu, 1500);
  creation.resolve(42);
  await f.ability.operation;
  assert.deepEqual(remote.results, [[1234, '']]);
  assert.equal(f.calls.startTun, 1);
});

test('latest tun options reach Go with the same platform-valid MTU and congestion controller', async () => {
  for (const [configured, ipv6, expected] of [[9000, false, 1500], [200, true, 1280], [200, false, 576]]) {
    const f = fixture();
    const options = Object.assign(f.vpnOptions(), { mtu: configured, ipv6, congestionController: 'bbr' });
    f.ability.handleStartService(options, 1234, f.remote());
    await f.ability.operation;
    assert.equal(f.calls.create[0].mtu, expected);
    assert.deepEqual(JSON.parse(f.calls.startTunArgs[7]), { mtu: expected, 'congestion-controller': 'bbr' });
    assert.equal(f.calls.startTunArgs[1](6, '192.0.2.1:123', '198.51.100.1:443'), 100);
    assert.equal(f.calls.startTunArgs[2](100), 'com.example.app');
  }
});

test('create rejection cannot produce a running timestamp', async () => {
  const f = fixture({ create: () => Promise.reject(new Error('Permission denied')) });
  const remote = f.remote();
  f.ability.handleStartService(f.vpnOptions(), 0, remote);
  await f.ability.operation;
  assert.equal(remote.results[0][0], 0);
  assert.match(remote.results[0][1], /Permission denied/);
  assert.equal(f.calls.startTun, 0);
});

test('TUN initialization failure destroys the created VPN', async () => {
  const f = fixture({ startTun: false });
  const remote = f.remote();
  f.ability.handleStartService(f.vpnOptions(), 0, remote);
  await f.ability.operation;
  assert.equal(remote.results[0][0], 0);
  assert.match(remote.results[0][1], /TUN initialization failed/);
  assert.equal(f.calls.destroy, 1);
});

test('stop issued during startup cancels the obsolete start and releases its VPN', async () => {
  const creation = deferred();
  const f = fixture({ create: () => creation.promise });
  const start = f.remote();
  const stop = f.remote();
  f.ability.handleStartService(f.vpnOptions(), 1234, start);
  await tick();
  f.ability.handleStopService(stop);
  await tick();
  assert.equal(stop.results.length, 0);
  creation.resolve(42);
  await f.ability.operation;
  assert.equal(start.results[0][0], 0);
  assert.match(start.results[0][1], /superseded/);
  assert.deepEqual(stop.results, [[0, '']]);
  assert.equal(f.calls.stopTun, 0);
  assert.equal(f.calls.destroy, 1);
  assert.equal(f.ability.runTime, 0);
});

test('destroy during startup cannot leave a running VPN behind', async () => {
  const creation = deferred();
  const f = fixture({ create: () => creation.promise });
  const remote = f.remote();
  f.ability.handleStartService(f.vpnOptions(), 0, remote);
  await tick();
  f.ability.onDestroy();
  creation.resolve(42);
  await f.ability.operation;
  assert.equal(remote.results[0][0], 0);
  assert.match(remote.results[0][1], /destroyed|superseded/);
  assert.equal(f.calls.startTun, 0);
  assert.equal(f.calls.destroy, 1);
});

test('stop reports completion only after asynchronous native TUN cleanup', async () => {
  const cleanup = deferred();
  const f = fixture({ stopTun: () => cleanup.promise });
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  const remote = f.remote();
  f.ability.handleStopService(remote);
  await tick();
  assert.equal(remote.results.length, 0);
  assert.equal(f.calls.destroy, 0);
  cleanup.resolve();
  await f.ability.operation;
  assert.deepEqual(remote.results, [[0, '']]);
  assert.equal(f.calls.destroy, 1);
});

test('duplicate start and stop requests are idempotent', async () => {
  const f = fixture();
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  f.ability.handleStartService(f.vpnOptions(), 0, f.remote());
  await f.ability.operation;
  f.ability.handleStopService(f.remote());
  f.ability.handleStopService(f.remote());
  await f.ability.operation;
  assert.equal(f.calls.create.length, 1);
  assert.equal(f.calls.stopTun, 1);
  assert.equal(f.calls.destroy, 1);
  assert.equal(f.calls.nets[0].unregisterCount, 1);
});

test('subscription failure rolls back both TUN and VPN', async () => {
  const f = fixture({ registerError: new Error('Network observer unavailable') });
  const remote = f.remote();
  f.ability.handleStartService(f.vpnOptions(), 0, remote);
  await f.ability.operation;
  assert.equal(remote.results[0][0], 0);
  assert.match(remote.results[0][1], /Network observer unavailable/);
  assert.equal(f.calls.stopTun, 1);
  assert.equal(f.calls.destroy, 1);
});

test('socket protection failure stops the tunnel and reports a service failure', async () => {
  const f = fixture({ protect: () => Promise.reject(new Error('Protect denied')) });
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  await assert.rejects(f.calls.protect(10), /Protect denied/);
  await new Promise((resolve) => setTimeout(resolve, 5));
  await f.ability.operation;
  assert.equal(f.calls.stopTun, 1);
  assert.equal(f.calls.destroy, 1);
  assert.equal(f.ability.runTime, 0);
  assert.match(f.calls.events[0].data, /Protect denied/);
  assert.equal(f.calls.events[0].event, 'HARMONY_VPN_ERROR');
});

test('socket owner races return an empty process instead of throwing through NAPI', () => {
  const f = fixture({ ownerError: true });
  assert.equal(f.ability.resolveUid(6, '192.0.2.1:10', '198.51.100.1:443'), -1);
  assert.equal(f.ability.resolvePackage(-1), '');
});

test('disconnect discards interrupted RPC chunks before another client connects', () => {
  const f = fixture({ realRpc: true });
  const service = f.ability.onConnect({});
  function chunk(last, bytes) {
    const ints = [7, bytes.length];
    return { readInt: () => ints.shift(), readBoolean: () => last, readByteArray: () => bytes };
  }
  assert.equal(service.reader.read(chunk(false, [65])), null);
  f.ability.onDisconnect({});
  assert.equal(service.reader.read(chunk(true, [66])), 'B');
});

test('network reconnect creates a fresh observer and ignores retired callbacks', async () => {
  const f = fixture();
  const Manager = f.load(path.join(etsRoot, 'managers/NetworkManager.ets')).default;
  const manager = new Manager();
  const dns = [];
  const update = (net, id, address) => {
    net.handlers.netAvailable({ netId: id });
    net.handlers.netConnectionPropertiesChange({ netHandle: { netId: id }, connectionProperties: { dnses: [{ address, family: 1 }] } });
  };
  await manager.subscribe((value) => dns.push(value));
  const first = f.calls.nets[0];
  update(first, 1, '192.0.2.53');
  await manager.unsubscribe();
  await manager.subscribe((value) => dns.push(value));
  const second = f.calls.nets[1];
  update(second, 2, '192.0.2.53');
  const count = dns.length;
  update(first, 3, '198.51.100.53');
  assert.equal(dns.length, count);
  assert.deepEqual(dns, ['192.0.2.53:53', '192.0.2.53:53']);
});

test('physical network transitions reset latest Mihomo network state even with unchanged DNS', async () => {
  const f = fixture();
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  const net = f.calls.nets[0];
  net.handlers.netAvailable({ netId: 1 });
  net.handlers.netLost({ netId: 1 });
  net.handlers.netAvailable({ netId: 2 });
  assert.equal(f.calls.networkReset, 3);
});

function wakeSubscriber(f) {
  return f.calls.subscribers.find((subscriber) => subscriber.options.events.includes('idle'));
}

async function fireTimers(f) {
  const pending = [...f.timers.entries()];
  for (const [id, callback] of pending) {
    if (f.timers.delete(id)) callback();
  }
  await tick();
}

test('same-network wake recovers a failed route without reconnecting the VPN', async () => {
  const f = fixture({ fakeTimers: true, probe: (reply) => reply(JSON.stringify({ result: { 'status-code': 0, error: 'timeout' } })) });
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  const power = wakeSubscriber(f);
  power.callback({ event: 'idle', parameters: { sleeping: true } });
  assert.equal(f.timers.size, 0);
  power.callback({ event: 'idle', parameters: { sleeping: false } });
  await fireTimers(f);
  assert.deepEqual(f.calls.probes, [{ method: 'probe', arguments: { url: '', timeout: 3000 } }]);
  assert.equal(f.calls.networkReset, 1);
  assert.equal(f.calls.create.length, 1);
  assert.equal(f.calls.stopTun, 0);
  assert.equal(f.ability.runTime, 1234);
});

test('screen-on covers a missed idle event and coalesces repeated wake events', async () => {
  let reply;
  const f = fixture({ fakeTimers: true, probe: (callback) => { reply = callback; } });
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  const power = wakeSubscriber(f);
  assert.ok(power.options.events.includes('screen-on'));
  power.callback({ event: 'screen-on' });
  power.callback({ event: 'idle', parameters: { sleeping: false } });
  assert.equal(f.timers.size, 1);
  await fireTimers(f);
  power.callback({ event: 'screen-on' });
  assert.equal(f.calls.probes.length, 1);
  reply(JSON.stringify({ result: { 'status-code': 401 } }));
  await tick();
  assert.equal(f.calls.networkReset, 0);
  assert.equal(f.timers.size, 0);
});

test('napping and sleeping never tear down an allowed background connection', async () => {
  const f = fixture({ fakeTimers: true });
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  const power = wakeSubscriber(f);
  power.callback({ event: 'idle', parameters: { napped: true, sleeping: false } });
  power.callback({ event: 'idle', parameters: { sleeping: true } });
  assert.equal(f.timers.size, 0);
  assert.equal(f.calls.probes.length, 0);
  assert.equal(f.calls.networkReset, 0);
});

test('stop cancels pending wake work and retires its power observer', async () => {
  const f = fixture({ fakeTimers: true });
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  const oldPower = wakeSubscriber(f);
  oldPower.callback({ event: 'screen-on' });
  f.ability.handleStopService(f.remote());
  await f.ability.operation;
  assert.equal(f.timers.size, 0);
  assert.equal(oldPower.unsubscribeCount, 1);
  f.ability.handleStartService(f.vpnOptions(), 2000, f.remote());
  await f.ability.operation;
  oldPower.callback({ event: 'screen-on' });
  await fireTimers(f);
  assert.equal(f.calls.probes.length, 0);
});

test('late failed wake probes cannot reset a stopped, restarted or destroyed service', async () => {
  for (const action of ['stop', 'restart', 'destroy']) {
    let reply;
    const f = fixture({ fakeTimers: true, probe: (callback) => { reply = callback; } });
    f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
    await f.ability.operation;
    wakeSubscriber(f).callback({ event: 'screen-on' });
    await fireTimers(f);
    if (action === 'destroy') f.ability.onDestroy();
    else f.ability.handleStopService(f.remote());
    await f.ability.operation;
    if (action === 'restart') {
      f.ability.handleStartService(f.vpnOptions(), 2000, f.remote());
      await f.ability.operation;
    }
    reply(JSON.stringify({ result: { 'status-code': 0, error: 'failed' } }));
    await tick();
    assert.equal(f.calls.networkReset, 0, action);
  }
});

test('a duplicate start during a wake probe rechecks the latest running intent', async () => {
  const replies = [];
  const f = fixture({ fakeTimers: true, probe: (reply) => replies.push(reply) });
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  wakeSubscriber(f).callback({ event: 'screen-on' });
  await fireTimers(f);
  f.ability.handleStartService(f.vpnOptions(), 0, f.remote());
  await f.ability.operation;
  replies[0](JSON.stringify({ result: { error: 'timeout' } }));
  await tick();
  assert.equal(f.calls.networkReset, 0);
  await fireTimers(f);
  replies[1](JSON.stringify({ result: { error: 'timeout' } }));
  await tick();
  assert.equal(f.calls.networkReset, 1);
  assert.equal(f.calls.create.length, 1);
  assert.equal(f.calls.stopTun, 0);
});

test('core RPC errors and missing probe slots do not count as a failed network', async () => {
  for (const response of [{ error: { message: 'Core unavailable' } }, { result: null }]) {
    const f = fixture({ fakeTimers: true, probe: (reply) => reply(JSON.stringify(response)) });
    f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
    await f.ability.operation;
    wakeSubscriber(f).callback({ event: 'screen-on' });
    await fireTimers(f);
    assert.equal(f.calls.networkReset, 0);
    assert.equal(f.ability.recovery, undefined);
    assert.equal(f.timers.size, 0);
  }
});

test('a lost core reply releases wake recovery so the next wake can retry', async () => {
  const f = fixture({ fakeTimers: true, probe() {} });
  f.ability.handleStartService(f.vpnOptions(), 1234, f.remote());
  await f.ability.operation;
  wakeSubscriber(f).callback({ event: 'screen-on' });
  await fireTimers(f);
  await fireTimers(f);
  assert.equal(f.calls.networkReset, 0);
  assert.equal(f.ability.recovery, undefined);
  wakeSubscriber(f).callback({ event: 'screen-on' });
  await fireTimers(f);
  assert.equal(f.calls.probes.length, 2);
  await fireTimers(f);
});

test('power observer failure rolls startup back rather than leaking the VPN', async () => {
  const f = fixture({ subscribe: () => Promise.reject(new Error('Power observer unavailable')) });
  const remote = f.remote();
  f.ability.handleStartService(f.vpnOptions(), 1234, remote);
  await f.ability.operation;
  assert.equal(remote.results[0][0], 0);
  assert.match(remote.results[0][1], /Power observer unavailable/);
  assert.equal(f.calls.stopTun, 1);
  assert.equal(f.calls.destroy, 1);
});

function servicePlugin(f, parent) {
  const Plugin = f.load(path.join(etsRoot, 'plugins/ServicePlugin.ets')).default;
  const plugin = new Plugin({ handleClearVpnNotification() {}, handleVpnNotification() {}, ...parent });
  plugin.onAttachedToEngine({ getBinaryMessenger: () => ({}) });
  return plugin;
}

test('mobile start acknowledges intent and reports failed establishment with its revision', async () => {
  const f = fixture();
  let callback;
  const plugin = servicePlugin(f, { handleStartService: (options, runTime, stub) => { callback = stub; return Promise.resolve(); } });
  const results = [];
  plugin.onMethodCall({ method: 'start', args: 7 }, { success: (value) => results.push(value) });
  assert.deepEqual(results, [true]);
  assert.equal(f.globalState.runState, 1);
  callback.onResult(0, 'VPN permission denied');
  assert.equal(f.globalState.runState, 2);
  const channel = f.calls.channels.get('com.follow.clash/service');
  assert.deepEqual(channel.messages, [{ method: 'stopped', args: 7 }]);
});

test('stale mobile start and stop completions cannot overwrite the latest command', async () => {
  const f = fixture();
  const starts = [];
  let stop;
  const plugin = servicePlugin(f, {
    handleStartService: (options, runTime, stub) => { starts.push(stub); return Promise.resolve(); },
    handleStopService: (stub) => { stop = stub; return Promise.resolve(); },
  });
  const result = { success() {} };
  plugin.onMethodCall({ method: 'start', args: 1 }, result);
  plugin.onMethodCall({ method: 'stop', args: 2 }, result);
  plugin.onMethodCall({ method: 'start', args: 3 }, result);
  starts[0].onResult(0, 'Superseded');
  starts[1].onResult(3000, '');
  stop.onResult(0, '');
  assert.equal(f.globalState.runTime, 3000);
  assert.equal(f.globalState.runState, 0);
  assert.deepEqual(f.calls.channels.get('com.follow.clash/service').messages, []);
});

test('status RPC errors are not cached successes', async () => {
  const f = fixture();
  const plugin = servicePlugin(f, { handleGetRunTime: () => Promise.reject(new Error('IPC unavailable')) });
  const results = [];
  plugin.onMethodCall({ method: 'getRunTime' }, { success: (value) => results.push(value), error: (code, message) => results.push([code, message]) });
  await tick();
  assert.deepEqual(results, [['VPN_STATUS_FAILED', 'IPC unavailable']]);
});

test('latest lightweight shared-state updates preserve native recovery setup parameters', () => {
  const f = fixture();
  const plugin = servicePlugin(f, {});
  const result = { success() {} };
  plugin.onMethodCall({ method: 'syncState', args: JSON.stringify({ setupParams: { 'test-url': 'https://example.com' }, showStopAction: true }) }, result);
  plugin.onMethodCall({ method: 'syncState', args: JSON.stringify({ setupParams: null, showStopAction: false }) }, result);
  assert.equal(f.globalState.state.setupParams['test-url'], 'https://example.com');
  assert.equal(f.globalState.state.showStopAction, false);
});

test('core channel responses and service events preserve the latest UTF8 JSON envelopes', async () => {
  const f = fixture();
  let reply;
  let event;
  let payload;
  const plugin = servicePlugin(f, {
    handleInvokeMethod: (data, stub) => { payload = data; reply = stub; return Promise.resolve(); },
    handleInit: (stub) => { event = stub; return Promise.resolve(); },
    setOnDisconnected() {},
  });
  const call = { id: '1', method: 'getConfig', arguments: null };
  const responses = [];
  f.calls.channels.get('com.follow.clash/core').handler.onMethodCall(
    { method: 'invokeMethod', args: JSON.stringify(call) }, { success: (bytes) => responses.push(JSON.parse(new TextDecoder().decode(bytes))) },
  );
  assert.equal(payload, JSON.stringify(call));
  reply.onResult(JSON.stringify({ id: '1', result: { name: '配置' } }));
  assert.deepEqual(responses, [{ id: '1', result: { name: '配置' } }]);
  plugin.onMethodCall({ method: 'init' }, { success() {} });
  const message = { method: 'message', arguments: [{ type: 'log', data: { payload: '日志' } }] };
  event.onResult(JSON.stringify(message));
  const sent = f.calls.channels.get('com.follow.clash/service').messages[0];
  assert.equal(sent.method, 'event');
  assert.deepEqual(JSON.parse(new TextDecoder().decode(sent.args)), message);
});

function notificationManager(f) {
  const Manager = f.load(path.join(etsRoot, 'managers/NotificationManager.ets')).default;
  f.globalState.runState = 0;
  return new Manager({ applicationInfo: { name: 'com.xiaomao.proxy' }, abilityInfo: { name: 'EntryAbility' } });
}

test('background task starts once for repeated start events', async () => {
  const start = deferred();
  const f = fixture({ backgroundStart: () => start.promise });
  const manager = notificationManager(f);
  const first = manager.startContinuousTask();
  const second = manager.startContinuousTask();
  await tick();
  assert.equal(f.calls.backgroundStart, 1);
  start.resolve();
  await Promise.all([first, second]);
  await manager.startContinuousTask();
  assert.equal(f.calls.backgroundStart, 1);
});

test('background task cannot start after stop while its WantAgent is pending', async () => {
  const agent = deferred();
  const f = fixture({ wantAgent: () => agent.promise });
  const manager = notificationManager(f);
  const start = manager.startContinuousTask();
  const stop = manager.stopContinuousTask();
  agent.resolve({});
  await Promise.all([start, stop]);
  assert.equal(f.calls.backgroundStart, 0);
});

test('unsubscribe awaits an in-flight background start and releases that task', async () => {
  const work = deferred();
  const f = fixture({ backgroundStart: () => work.promise });
  const manager = notificationManager(f);
  const start = manager.startContinuousTask();
  await tick();
  assert.equal(f.calls.backgroundStart, 1);
  const stop = manager.unsubscribe();
  work.resolve();
  await Promise.all([start, stop]);
  assert.equal(f.calls.backgroundStop, 1);
});

test('stop removes cancelled-task restart timers and callbacks', async () => {
  const f = fixture({ fakeTimers: true });
  const manager = notificationManager(f);
  await manager.startContinuousTask();
  f.calls.backgroundCancel();
  assert.equal(f.timers.size, 1);
  await manager.stopContinuousTask();
  assert.equal(f.timers.size, 0);
  assert.equal(f.calls.backgroundCancel, undefined);
  assert.equal(f.calls.backgroundStart, 1);
});

test('a pending notification cannot publish after it was cleared', async () => {
  const agent = deferred();
  const f = fixture({ wantAgent: () => agent.promise, fakeTimers: true });
  const manager = notificationManager(f);
  manager.applyParams(JSON.stringify({ phase: 'connected', title: '野猫代理', content: '', configHint: '', showActions: false }));
  const publish = manager.publishNow();
  manager.clearNotification();
  agent.resolve({});
  await publish;
  assert.equal(f.calls.notificationPublish, 0);
});
