import { commonEventManager } from "@kit.BasicServicesKit"

export default class PowerManager {
  private subscriber: commonEventManager.CommonEventSubscriber | undefined
  private subscription: Promise<void> | undefined

  subscribe(callback: (idle: boolean) => void): Promise<void> {
    if (this.subscription) return this.subscription
    const subscriber = commonEventManager.createSubscriberSync({
      events: [commonEventManager.Support.COMMON_EVENT_DEVICE_IDLE_MODE_CHANGED]
    } as commonEventManager.CommonEventSubscribeInfo)
    this.subscriber = subscriber
    this.subscription = commonEventManager.subscribeToEvent(subscriber, (commonEventData: commonEventManager.CommonEventData) => {
      if (this.subscriber === subscriber) callback(commonEventData.parameters?.sleeping === true)
    }).catch((err: Error) => {
      this.subscriber = undefined
      this.subscription = undefined
      throw err
    })
    return this.subscription
  }

  unsubscribe(): Promise<void> {
    const subscriber = this.subscriber
    if (!subscriber) return Promise.resolve()
    return (this.subscription ?? Promise.resolve()).then(() => new Promise<void>((resolve, reject) => {
      commonEventManager.unsubscribe(subscriber, (err: Error) => {
        if (err) reject(err)
        else resolve()
      })
    })).then(() => {
      this.subscriber = undefined
      this.subscription = undefined
    })
  }
}
