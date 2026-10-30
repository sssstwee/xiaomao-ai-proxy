import { vpnExtension, VpnExtensionAbility, connection } from '@kit.NetworkKit'
import { Want, bundleManager } from '@kit.AbilityKit'
import { rpc } from '@kit.IPCKit'
import { deviceInfo } from '@kit.BasicServicesKit'
import { setEventListener, invokeAction, startTUN, stopTun, forceGC, suspend, updateDns, quickSetup } from 'core'
import { AccessControlMode, VpnOptions } from '../models/State'
import { ChunkedSender, ChunkedReader } from '../utils/Rpc'
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import PowerManager from '../managers/PowerManager'
import NetworkManager from '../managers/NetworkManager'
import { publishEvent } from '../utils/Event'

const IPV4_ADDRESS = "172.19.0.1/30"
const IPV6_ADDRESS = "fdfe:dcba:9876::1/126"
const DNS = "172.19.0.2"
const DNS6 = "fdfe:dcba:9876::2"
const NET_ANY = "0.0.0.0"
const NET_ANY6 = "::"

export enum RPCType{
  invokeAction,
  quickSetup,
  updateNotificationParams,
  startService,
  stopService,
  setEventListener,
  setCrashlytics,
  getRunTime,
}

export class ServiceStub extends rpc.RemoteObject {
  private parent: VpnExtAbility
  private reader: ChunkedReader = new ChunkedReader()

  constructor(descriptor: string, parent: VpnExtAbility) {
    super(descriptor)
    this.parent = parent
  }

  clearPendingMessages(): void {
    this.reader.clear()
  }

  onRemoteMessageRequest(code: number, send: rpc.MessageSequence, reply: rpc.MessageSequence, option: rpc.MessageOption): boolean | Promise<boolean> {
    if (code === RPCType.setEventListener) {
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleSetEventListener(remote)
      return true
    } else if (code === RPCType.invokeAction) {
      const data = this.reader.read(send)
      if (data === null) return true
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleInvokeAction(data, remote)
      return true
    } else if (code === RPCType.startService) {
      const raw = this.reader.read(send)
      if (raw === null) return true
      const vpnOptions = JSON.parse(raw) as VpnOptions
      const runTime = send.readLong()
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleStartService(vpnOptions, runTime, remote)
      return true
    } else if (code === RPCType.stopService) {
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleStopService(remote)
      return true
    } else if (code === RPCType.getRunTime) {
      this.parent.handleGetRunTime(reply)
      return true
    } else if (code === RPCType.quickSetup) {
      const setupParams = this.reader.read(send)
      if (setupParams === null) return true
      const initParams = send.readString()
      const remote = send.readRemoteObject() as rpc.RemoteObject
      this.parent.handleQuickSetup(initParams, setupParams, remote)
      return true
    } else if (code === RPCType.updateNotificationParams) {
      return true
    } else if (code === RPCType.setCrashlytics) {
      return true
    } else {
      return false
    }
  }
}

export default class VpnExtAbility extends VpnExtensionAbility {
  private service: ServiceStub | undefined
  private vpnConnection: vpnExtension.VpnConnection | undefined
  private vpnCreated: boolean = false
  private tunStarted: boolean = false
  private destroyed: boolean = false
  private operation: Promise<void> = Promise.resolve()
  private protectFailurePending: boolean = false
  private powerManager: PowerManager | undefined
  private networkManager: NetworkManager | undefined
  private runTime: number = 0
  private sender: ChunkedSender = new ChunkedSender()
  private uidBundleNameMap: Map<number, string> = new Map<number, string>()

  onCreate(want: Want): void {
    this.destroyed = false
    this.vpnConnection = vpnExtension.createVpnConnection(this.context)
    this.powerManager = new PowerManager()
    this.networkManager = new NetworkManager()
  }

  onDestroy(): void {
    this.destroyed = true
    this.service?.clearPendingMessages()
    setEventListener()
    this.enqueue(async (): Promise<void> => { await this.stopService() })
  }

  onConnect(want: Want): rpc.RemoteObject {
    if (!this.service) this.service = new ServiceStub("ServiceStub", this)
    return this.service
  }

  onDisconnect(want: Want): void {
    this.service?.clearPendingMessages()
    setEventListener()
  }

  onMemoryLevel(level: AbilityConstant.MemoryLevel): void {
    if (level === AbilityConstant.MemoryLevel.MEMORY_LEVEL_CRITICAL) forceGC()
  }

  private toLinkAddress(cidr: string, family: number): vpnExtension.LinkAddress {
    const parts = cidr.split('/')
    const address: connection.NetAddress = { address: parts[0], family }
    return { address, prefixLength: Number(parts[1]) }
  }

  private toRouteInfo(cidr: string, family: number): vpnExtension.RouteInfo {
    const destination = this.toLinkAddress(cidr, family)
    const gateway: connection.NetAddress = { address: '', family }
    return {
      interface: '',
      destination,
      gateway,
      hasGateway: false,
      isDefaultRoute: destination.prefixLength === 0,
    }
  }

  private toVpnConfig(options: VpnOptions): vpnExtension.VpnConfig {
    const ipv4RouteAddress = options.routeAddress.filter((it) => !it.includes(':'))
    const ipv6RouteAddress = options.routeAddress.filter((it) => it.includes(':'))

    const addresses: vpnExtension.LinkAddress[] = [this.toLinkAddress(IPV4_ADDRESS, 1)]
    const routes: vpnExtension.RouteInfo[] = ipv4RouteAddress.length > 0
      ? ipv4RouteAddress.map((it) => this.toRouteInfo(it, 1))
      : [this.toRouteInfo(`${NET_ANY}/0`, 1)]
    const dnsAddresses: string[] = [DNS]

    if (options.ipv6) {
      addresses.push(this.toLinkAddress(IPV6_ADDRESS, 2))
      routes.push(...(ipv6RouteAddress.length > 0
        ? ipv6RouteAddress.map((it) => this.toRouteInfo(it, 2))
        : [this.toRouteInfo(`${NET_ANY6}/0`, 2)]))
      dnsAddresses.push(DNS6)
    }

    const config: vpnExtension.VpnConfig = {
      addresses,
      routes,
      dnsAddresses,
      // NetworkKit accepts MTUs from 576 to 1500; keep the virtual interface valid.
      mtu: 1500,
      isIPv4Accepted: true,
      isIPv6Accepted: options.ipv6,
      isBlocking: !options.allowBypass,
    }

    const accessControl = options.accessControlProps
    if (accessControl.enable) {
      if (accessControl.mode === AccessControlMode.ACCEPT_SELECTED) {
        config.trustedApplications = [...accessControl.acceptList, this.context.applicationInfo.name]
      } else {
        config.blockedApplications = accessControl.rejectList.filter((it) => it !== this.context.applicationInfo.name)
      }
    }

    return config
  }

  private toTunAddress(options: VpnOptions): string {
    const addresses = [IPV4_ADDRESS]
    if (options.ipv6) {
      addresses.push(IPV6_ADDRESS)
    }
    return addresses.join(',')
  }

  private toTunDns(options: VpnOptions): string {
    if (options.dnsHijacking) {
      return NET_ANY
    }
    const dns = [DNS]
    if (options.ipv6) {
      dns.push(DNS6)
    }
    return dns.join(',')
  }

  private toNetAddress(addr: string): connection.NetAddress {
    const separator = addr.lastIndexOf(':')
    const host = addr.slice(0, separator)
    const port = Number(addr.slice(separator + 1))
    const address = host.startsWith('[') && host.endsWith(']') ? host.slice(1, -1) : host
    const family = address.includes(':') ? 2 : 1
    return { address, family, port }
  }

  private resolverProcess(protocol: number, source: string, target: string, uid: number): string {
    let nextUid = uid
    try {
      if (deviceInfo.sdkApiVersion >= 23) {
        nextUid = connection.getConnectOwnerUidSync(protocol, this.toNetAddress(source), this.toNetAddress(target))
      }
    } catch (err) {
      // A socket can disappear between TUN delivery and the owner lookup.
      return ''
    }
    if (nextUid === -1) return ''
    if (!this.uidBundleNameMap.has(nextUid)) {
      try {
        this.uidBundleNameMap.set(nextUid, bundleManager.getBundleNameByUidSync(nextUid))
      } catch (err) {
        this.uidBundleNameMap.set(nextUid, '')
      }
    }

    return this.uidBundleNameMap.get(nextUid) ?? ''
  }

  private sendCallback(remote: rpc.RemoteObject, data: string): void {
    this.sender.send(remote, 0, data, null).catch((err: Error) => {
      console.error(`Send core callback failed: ${err.message}`)
    })
  }

  private sendResult(remote: rpc.RemoteObject, runTime: number, error: string = ''): void {
    const options = new rpc.MessageOption()
    const send = rpc.MessageSequence.create()
    const reply = rpc.MessageSequence.create()
    options.setAsync(false)
    send.writeLong(runTime)
    send.writeString(error)
    remote.sendMessageRequest(0, send, reply, options).catch((err: Error) => {
      console.error(`Send VPN result failed: ${err.message}`)
    }).finally(() => {
      send.reclaim()
      reply.reclaim()
    })
  }

  handleSetEventListener(remote: rpc.RemoteObject): void {
    setEventListener((callbackData: string) => { this.sendCallback(remote, callbackData) })
  }

  handleInvokeAction(data: string, remote: rpc.RemoteObject): void {
    invokeAction((callbackData: string) => { this.sendCallback(remote, callbackData) }, data)
  }

  private enqueue(operation: () => Promise<void>): void {
    this.operation = this.operation.then(operation).catch((err: Error) => {
      console.error(`VPN lifecycle failed: ${err.message}`)
    })
  }

  private protectSocket(socketFd: number): Promise<void> {
    const vpnConnection = this.vpnConnection
    if (!vpnConnection) return Promise.reject(new Error('VPN connection is unavailable'))
    return Promise.resolve().then(() => vpnConnection.protect(socketFd)).catch((err: Error) => {
      if (!this.protectFailurePending) {
        this.protectFailurePending = true
        // Let the native callback settle before stopTun waits for outstanding callbacks.
        setTimeout(() => {
          this.enqueue(async (): Promise<void> => {
            try {
              await this.stopService()
            } finally {
              await publishEvent('HARMONY_VPN_ERROR', `Protect socket failed: ${err.message}`)
            }
          })
        }, 0)
      }
      throw err
    })
  }

  private async stopService(): Promise<void> {
    this.runTime = 0
    this.uidBundleNameMap.clear()
    let error = ''
    if (this.tunStarted) {
      try {
        await stopTun()
        this.tunStarted = false
      } catch (err) { error = `Stop TUN failed: ${err}` }
    }
    try { await this.powerManager?.unsubscribe() } catch (err) { error = error || `Power cleanup failed: ${err}` }
    try { await this.networkManager?.unsubscribe() } catch (err) { error = error || `Network cleanup failed: ${err}` }
    if (this.vpnCreated) {
      try {
        await this.vpnConnection?.destroy()
        this.vpnCreated = false
      } catch (err) { error = error || `Destroy VPN failed: ${err}` }
    }
    if (error) throw new Error(error)
  }

  handleStartService(vpnOptions: VpnOptions, runTime: number, remote: rpc.RemoteObject): void {
    this.enqueue(async (): Promise<void> => {
      try {
        if (this.destroyed) throw new Error('VPN service has been destroyed')
        if (this.runTime !== 0) {
          this.sendResult(remote, this.runTime)
          return
        }
        // Retry cleanup after an earlier destroy failure before creating another VPN.
        if (this.vpnCreated || this.tunStarted) await this.stopService()
        this.protectFailurePending = false
        if (vpnOptions.enable) {
          const vpnConnection = this.vpnConnection
          if (!vpnConnection) throw new Error('VPN connection is unavailable')
          const fd = await vpnConnection.create(this.toVpnConfig(vpnOptions))
          this.vpnCreated = true
          if (this.destroyed) throw new Error('VPN service was destroyed during startup')
          this.tunStarted = startTUN(
            (socketFd: number): Promise<void> => this.protectSocket(socketFd),
            (protocol: number, source: string, target: string, uid: number) => this.resolverProcess(protocol, source, target, uid),
            fd,
            vpnOptions.stack,
            this.toTunAddress(vpnOptions),
            this.toTunDns(vpnOptions),
          )
          if (!this.tunStarted) throw new Error('Mihomo TUN initialization failed')
        }
        await this.powerManager?.subscribe(suspend)
        await this.networkManager?.subscribe(updateDns)
        if (this.destroyed) throw new Error('VPN service was destroyed during startup')
        this.runTime = runTime > 0 ? runTime : Date.now()
        this.sendResult(remote, this.runTime)
      } catch (err) {
        let error = `${err}`
        try { await this.stopService() } catch (cleanupError) { error += `; ${cleanupError}` }
        this.sendResult(remote, 0, error)
      }
    })
  }

  handleStopService(remote: rpc.RemoteObject): void {
    this.enqueue(async (): Promise<void> => {
      try {
        await this.stopService()
        this.sendResult(remote, 0)
      } catch (err) {
        this.sendResult(remote, 0, `${err}`)
      }
    })
  }

  handleGetRunTime(reply: rpc.MessageSequence): void {
    reply.writeLong(this.runTime)
  }

  handleQuickSetup(initParams: string, setupParams: string, remote: rpc.RemoteObject): void {
    quickSetup((callbackData: string) => { this.sendCallback(remote, callbackData) }, initParams, setupParams)
  }
}

