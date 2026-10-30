import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { CallbackStub, ResultStub } from '../entryability/EntryAbility'
import { State, VpnOptions } from '../models/State'
import { commonEventManager } from '@kit.BasicServicesKit'
import { util } from '@kit.ArkTS'
import { publishEvent } from '../utils/Event'
import { globalState, RunState } from '../GlobalState';
import EntryAbility from '../entryability/EntryAbility';

class CoreMethodCallHandler implements MethodCallHandler {
  private callback: (call: MethodCall, result: MethodResult) => void

  constructor(callback: (call: MethodCall, result: MethodResult) => void) {
    this.callback = callback
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    this.callback(call, result)
  }
}

export default class ServicePlugin implements FlutterPlugin, MethodCallHandler {
  private parent: EntryAbility
  private channel: MethodChannel | undefined
  private coreChannel: MethodChannel | undefined
  private subscriber: commonEventManager.CommonEventSubscriber | undefined
  private commandRevision: number = 0
  private startRequested: boolean = false

  constructor(entryAbility: EntryAbility) { this.parent = entryAbility }

  getUniqueClassName(): string { return 'ServicePlugin' }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'com.follow.clash/service')
    this.channel.setMethodCallHandler(this)
    this.coreChannel = new MethodChannel(binding.getBinaryMessenger(), 'com.follow.clash/core')
    const coreHandler = new CoreMethodCallHandler((call: MethodCall, result: MethodResult): void => {
      this.onCoreMethodCall(call, result)
    })
    this.coreChannel.setMethodCallHandler(coreHandler)
    this.subscriber = commonEventManager.createSubscriberSync({
      events: ['HARMONY_NOTIF_ACTION', 'HARMONY_VPN_ERROR'],
    } as commonEventManager.CommonEventSubscribeInfo)
    commonEventManager.subscribeToEvent(this.subscriber, (event: commonEventManager.CommonEventData) => {
      if (event.event === 'HARMONY_VPN_ERROR') {
        this.reportStopped()
      } else if (event.data === 'disconnect') {
        this.stopNative(true)
      }
    })
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.subscriber) {
      commonEventManager.unsubscribe(this.subscriber)
      this.subscriber = undefined
    }
    this.channel?.setMethodCallHandler(null)
    this.coreChannel?.setMethodCallHandler(null)
    // Flutter observation ends here; an established VPN remains owned by its service.
    this.parent.handleShutdown().catch((err: Error) => console.error(`Detach core listener failed: ${err.message}`))
  }

  private reportStopped(): void {
    globalState.runTime = 0
    globalState.runState = RunState.stop
    this.startRequested = false
    this.parent.handleClearVpnNotification()
    this.channel?.invokeMethod('stopped', this.commandRevision)
    publishEvent('SERVICE_STOP', '')
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'init') {
      this.handleInit(result)
    } else if (call.method === 'shutdown') {
      this.parent.handleShutdown().then(() => result.success(true)).catch((err: Error) => {
        result.error('CORE_SHUTDOWN_FAILED', err.message, null)
      })
    } else if (call.method === 'syncState') {
      try {
        const state = JSON.parse(call.args) as State
        state.setupParams = state.setupParams ?? globalState.state.setupParams
        globalState.state = state
        result.success('')
      } catch (err) { result.success(`Invalid shared state: ${err}`) }
    } else if (call.method === 'start' || call.method === 'stop') {
      this.commandRevision = typeof call.args === 'number' ? call.args as number : this.commandRevision + 1
      if (call.method === 'start') this.startNative()
      else this.stopNative(false)
      // Matches FlClash mobile: this acknowledges intent, not TUN establishment.
      result.success(true)
    } else if (call.method === 'getRunTime') {
      this.parent.handleGetRunTime().then((runTime: number) => {
        globalState.runTime = runTime
        globalState.runState = runTime !== 0 ? RunState.start : RunState.stop
        result.success(runTime)
      }).catch((err: Error) => result.error('VPN_STATUS_FAILED', err.message, null))
    } else {
      result.notImplemented()
    }
  }

  private onCoreMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'invokeMethod') { result.notImplemented(); return }
    if (typeof call.args !== 'string') {
      result.error('INVALID_ARGUMENT', 'Core method payload must be a string', null)
      return
    }
    const callback = new CallbackStub('invokeMethod', (data: string) => {
      result.success(util.TextEncoder.create().encodeInto(data))
    })
    this.parent.handleInvokeMethod(call.args as string, callback).catch((err: Error) => {
      result.error('CORE_ERROR', err.message, null)
    })
  }

  private handleInit(result: MethodResult): void {
    const callback = new CallbackStub('setEventListener', (data: string) => {
      this.channel?.invokeMethod('event', util.TextEncoder.create().encodeInto(data))
    })
    this.parent.handleInit(callback).then(() => result.success('')).catch((err: Error) => result.success(err.message))
    this.parent.setOnDisconnected(() => this.reportStopped())
  }

  private startNative(): void {
    const revision = this.commandRevision
    this.startRequested = true
    globalState.runState = RunState.pending
    const finish = (runTime: number, error: string): void => {
      if (revision !== this.commandRevision || !this.startRequested) return
      globalState.runTime = runTime
      globalState.runState = runTime !== 0 ? RunState.start : RunState.stop
      if (error || runTime === 0) {
        this.reportStopped()
      } else {
        this.parent.handleVpnNotification(JSON.stringify({
          phase: 'connected', title: globalState.state.currentProfileName,
          content: '', configHint: '', showActions: globalState.state.showStopAction,
        }))
        publishEvent('SERVICE_START', '')
      }
    }
    const callback = new ResultStub('start', finish)
    this.parent.handleStartService(globalState.state?.vpnOptions ?? new VpnOptions(), globalState.runTime, callback)
      .catch((err: Error) => finish(0, err.message))
  }

  private stopNative(report: boolean): void {
    const revision = this.commandRevision
    this.startRequested = false
    globalState.runState = RunState.pending
    const finish = (runTime: number, error: string): void => {
      if (revision !== this.commandRevision || this.startRequested) return
      globalState.runTime = runTime
      globalState.runState = runTime !== 0 ? RunState.start : RunState.stop
      this.parent.handleClearVpnNotification()
      publishEvent('SERVICE_STOP', '')
      if (report || error) this.reportStopped()
    }
    this.parent.handleStopService(new ResultStub('stop', finish)).catch((err: Error) => finish(0, err.message))
  }
}
