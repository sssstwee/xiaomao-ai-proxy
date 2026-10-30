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
  const calls = { create: [], destroy: 0, startTun: 0, stopTun: 0, dns: [], events: [], nets: [], subscribers: [], backgroundStart: 0, backgroundStop: 0 };
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
    '@kit.NotificationKit': { notificationManager: { cancel: (id, callback) => callback() } },
    '@kit.IPCKit': { rpc: { RemoteObject: class {}, MessageOption: class { setAsync() {} }, MessageSequence } },
    '@kit.BasicServicesKit': {
      deviceInfo: { sdkApiVersion: 26 },
      commonEventManager: {
        Support: { COMMON_EVENT_DEVICE_IDLE_MODE_CHANGED: 'idle' },
        createSubscriberSync: (options) => { const subscriber = { options }; calls.subscribers.push(subscriber); return subscriber; },
        subscribeToEvent: (subscriber, callback) => { subscriber.callback = callback; return Promise.resolve(); },
        unsubscribe: (subscriber, callback) => { subscriber.unsubscribeCount = (subscriber.unsubscribeCount ?? 0) + 1; callback?.(); },
        publish: (event, options, callback) => { calls.events.push({ event, data: options.data }); callback(); },
      },
    },
    '@ohos.app.ability.AbilityConstant': { default: { MemoryLevel: { MEMORY_LEVEL_CRITICAL: 4 } } },
    '@ohos/flutter_ohos': { MethodChannel: class {}, FlutterAbility: class {} },
    '@kit.ArkTS': { util: {
      TextEncoder: { create: () => ({ encodeInto: (value) => new TextEncoder().encode(value) }) },
      TextDecoder: { create: () => ({ decodeToString: (value) => new TextDecoder().decode(value) }) },
    } },
    core: {
      startTUN: (protect) => { calls.startTun++; calls.protect = protect; return overrides.startTun ?? true; },
      stopTun: () => { calls.stopTun++; return overrides.stopTun?.(); },
      suspend() {}, updateDns: (value) => calls.dns.push(value),
      setEventListener() {}, invokeAction() {}, quickSetup() {}, forceGC() {},
    },
  };
  const fileMocks = new Map([
    [path.join(etsRoot, 'utils/Rpc.ets'), { ChunkedSender: class {}, ChunkedReader: class {} }],
    [path.join(etsRoot, 'entryability/EntryAbility.ets'), { ResultStub, CallbackStub: class {} }],
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

test('stop issued during startup is serialized after creation and releases TUN', async () => {
  const creation = deferred();
  const f = fixture({ create: () => creation.promise });
  const start = f.remote();
  const stop = f.remote();
  f.ability.handleStartService(f.vpnOptions(), 1234, start);
  f.ability.handleStopService(stop);
  await tick();
  assert.equal(stop.results.length, 0);
  creation.resolve(42);
  await f.ability.operation;
  assert.deepEqual(start.results, [[1234, '']]);
  assert.deepEqual(stop.results, [[0, '']]);
  assert.equal(f.calls.stopTun, 1);
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
  assert.match(remote.results[0][1], /destroyed/);
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
  f.ability.handleStartService(f.vpnOptions(), 0, f.remote());
  f.ability.handleStopService(f.remote());
  f.ability.handleStopService(f.remote());
  await f.ability.operation;
  assert.equal(f.calls.create.length, 1);
  assert.equal(f.calls.stopTun, 1);
  assert.equal(f.calls.destroy, 1);
  assert.equal(f.calls.nets[0].unregisterCount, 1);
  assert.equal(f.calls.subscribers[0].unsubscribeCount, 1);
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

test('socket protection failure stops the tunnel and reports a service crash', async () => {
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
  assert.equal(f.ability.resolverProcess(6, '192.0.2.1:10', '198.51.100.1:443', -1), '');
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

test('method channel start waits for the native callback and forwards its error', async () => {
  const f = fixture();
  const Plugin = f.load(path.join(etsRoot, 'plugins/ServicePlugin.ets')).default;
  let callback;
  const parent = { handleStartService: (options, runTime, stub) => { callback = stub; return Promise.resolve(); } };
  const plugin = new Plugin(parent);
  const results = [];
  plugin.onMethodCall({ method: 'start' }, { success: (value) => results.push(value), error: (code, message) => results.push([code, message]) });
  await tick();
  assert.equal(results.length, 0);
  callback.onResult(0, 'VPN permission denied');
  assert.deepEqual(results, [['VPN_START_FAILED', 'VPN permission denied']]);
  assert.equal(f.globalState.runState, 2);
});

test('method channel stop waits for cleanup and status RPC errors are not cached successes', async () => {
  const f = fixture();
  const Plugin = f.load(path.join(etsRoot, 'plugins/ServicePlugin.ets')).default;
  let callback;
  const parent = {
    handleStopService: (stub) => { callback = stub; return Promise.resolve(); },
    handleGetRunTime: () => Promise.reject(new Error('IPC unavailable')),
  };
  const plugin = new Plugin(parent);
  const results = [];
  const result = { success: (value) => results.push(value), error: (code, message) => results.push([code, message]) };
  plugin.onMethodCall({ method: 'stop' }, result);
  await tick();
  assert.equal(results.length, 0);
  callback.onResult(0, '');
  assert.deepEqual(results, [true]);
  plugin.onMethodCall({ method: 'getRunTime' }, result);
  await tick();
  assert.deepEqual(results[1], ['VPN_STATUS_FAILED', 'IPC unavailable']);
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
