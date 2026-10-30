import { connection } from "@kit.NetworkKit";
import { Network } from "../models/Network"

export default class NetworkManager {
  private netConnection: connection.NetConnection | undefined
  private subscription: Promise<void> | undefined
  private networkMap: Map<number, Network> = new Map<number, Network>()
  private preDnsList: string[] = []

  private asSocketAddressText(address: connection.NetAddress, port: number): string {
    if (address.family === 2) {
      return `[${address.address}]:${port}`
    }
    return `${address.address}:${port}`
  }

  private handleNetworkUpdate(callback: (s: string) => void): void {
    const networks = Array.from(this.networkMap.values())
    const best = networks.reduce((previousValue: Network, currentValue: Network) => {
      return Math.max(-1, ...currentValue.bearerTypes) > Math.max(-1, ...previousValue.bearerTypes) ? currentValue : previousValue
    }, networks[0] ?? new Network())
    const dnsList = best.dnses.map((address: connection.NetAddress) => this.asSocketAddressText(address, 53))
    if (dnsList.length === this.preDnsList.length && dnsList.every((dns: string, i: number) => dns === this.preDnsList[i])) return
    this.preDnsList = dnsList
    callback(Array.from(new Set(dnsList)).join(","))
  }

  subscribe(callback: (s: string) => void, onNetworkChanged?: () => void): Promise<void> {
    if (this.subscription) return this.subscription
    // A fresh observer avoids accumulating handlers across VPN reconnects.
    const netConnection = connection.createNetConnection()
    this.netConnection = netConnection
    this.subscription = new Promise<void>((resolve, reject) => {
      netConnection.on("netAvailable", (netHandle: connection.NetHandle) => {
        if (this.netConnection !== netConnection) return
        if (netHandle?.netId) {
          this.networkMap.set(netHandle.netId, new Network())
          onNetworkChanged?.()
          this.handleNetworkUpdate(callback)
        }
      })

      netConnection.on("netCapabilitiesChange", (netCapabilityInfo: connection.NetCapabilityInfo) => {
        if (this.netConnection !== netConnection) return
        const netId = netCapabilityInfo?.netHandle?.netId
        const bearerTypes = netCapabilityInfo?.netCap?.bearerTypes
        if (netId && bearerTypes) {
          const network = this.networkMap.get(netId)
          if (network) network.bearerTypes = bearerTypes
          this.handleNetworkUpdate(callback)
        }
      })

      netConnection.on("netConnectionPropertiesChange", (netConnectionPropertyInfo: connection.NetConnectionPropertyInfo) => {
        if (this.netConnection !== netConnection) return
        const netId = netConnectionPropertyInfo?.netHandle?.netId
        const dnses = netConnectionPropertyInfo?.connectionProperties?.dnses
        if (netId && dnses) {
          const network = this.networkMap.get(netId)
          if (network) network.dnses = dnses
          this.handleNetworkUpdate(callback)
        }
      })

      netConnection.on("netLost", (netHandle: connection.NetHandle) => {
        if (this.netConnection !== netConnection) return
        if (netHandle?.netId) {
          this.networkMap.delete(netHandle.netId)
          onNetworkChanged?.()
          this.handleNetworkUpdate(callback)
        }
      })

      netConnection.register((err: Error) => {
        if(err) {
          reject(err)
        } else {
          resolve()
        }
      })
    }).catch((err: Error) => {
      this.netConnection = undefined
      this.subscription = undefined
      this.networkMap.clear()
      this.preDnsList = []
      throw err
    })
    return this.subscription
  }

  unsubscribe(): Promise<void> {
    const netConnection = this.netConnection
    if (!netConnection) return Promise.resolve()
    return (this.subscription ?? Promise.resolve()).then(() => new Promise<void>((resolve, reject) => {
      netConnection.unregister((err: Error) => {
        if (err) {
          reject(err)
        } else {
          resolve()
        }
      })
    })).then(() => {
      this.netConnection = undefined
      this.subscription = undefined
      this.networkMap.clear()
      this.preDnsList = []
    })
  }
}
