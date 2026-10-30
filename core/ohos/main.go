//go:build openharmony && cgo

package main

/*
#include "bridge.h"
*/
import "C"

import (
	"core"
	"sync"
	"unsafe"
)

func main() {}

func takeString(value *C.char) string {
	if value == nil {
		return ""
	}
	defer C.free_string(value)
	return C.GoString(value)
}

func sendResult(handler unsafe.Pointer, data []byte) {
	value := C.CString(string(data))
	defer C.free(unsafe.Pointer(value))
	C.result(handler, value)
}

//export invokeMethod
func invokeMethod(handler unsafe.Pointer, payload *C.char) {
	core.InvokeMethod(takeString(payload), func(data []byte) {
		defer C.release_object(handler)
		sendResult(handler, data)
	})
}

var eventOwner struct {
	sync.Mutex
	handler unsafe.Pointer
}

//export setEventListener
func setEventListener(handler unsafe.Pointer) {
	eventOwner.Lock()
	defer eventOwner.Unlock()
	// Wait for the previous Go delivery before releasing its native callbacks.
	core.SetEventListener(nil)
	if eventOwner.handler != nil {
		C.release_object(eventOwner.handler)
	}
	eventOwner.handler = handler
	if handler != nil {
		core.SetEventListener(func(data []byte) { sendResult(handler, data) })
	}
}

type tunCallbacks struct {
	handler unsafe.Pointer
}

func (callbacks tunCallbacks) Protect(fd int) bool {
	return bool(C.protect(callbacks.handler, C.int(fd)))
}

func (callbacks tunCallbacks) ResolveUid(protocol int, source, target string) int {
	sourceValue, targetValue := C.CString(source), C.CString(target)
	defer C.free(unsafe.Pointer(sourceValue))
	defer C.free(unsafe.Pointer(targetValue))
	return int(C.resolve_uid(callbacks.handler, C.int(protocol), sourceValue, targetValue))
}

func (callbacks tunCallbacks) ResolvePackage(uid int) string {
	return takeString(C.resolve_package(callbacks.handler, C.int(uid)))
}

var tunOwner struct {
	sync.Mutex
	handler unsafe.Pointer
}

//export startTUN
func startTUN(handler unsafe.Pointer, fd C.int, stack, address, dns, options *C.char) bool {
	tunOwner.Lock()
	defer tunOwner.Unlock()
	previous := tunOwner.handler
	started := core.StartTun(tunCallbacks{handler}, int(fd), takeString(stack), takeString(address), takeString(dns), takeString(options))
	if previous != nil {
		C.release_object(previous)
	}
	tunOwner.handler = nil
	if !started {
		core.StopTun()
		if handler != nil {
			C.release_object(handler)
		}
		return false
	}
	tunOwner.handler = handler
	return true
}

//export stopTun
func stopTun() {
	tunOwner.Lock()
	defer tunOwner.Unlock()
	core.StopTun()
	if tunOwner.handler != nil {
		C.release_object(tunOwner.handler)
		tunOwner.handler = nil
	}
}

//export quickSetup
func quickSetup(handler unsafe.Pointer, initParams, setupParams *C.char) {
	core.QuickSetup(takeString(initParams), takeString(setupParams), func(message string) {
		defer C.release_object(handler)
		sendResult(handler, []byte(message))
	})
}

//export getTotalTraffic
func getTotalTraffic(onlyProxy bool) *C.char {
	// The native caller copies the value and frees the returned allocation.
	return C.CString(core.GetTotalTraffic(onlyProxy))
}

//export getTraffic
func getTraffic(onlyProxy bool) *C.char {
	return C.CString(core.GetTraffic(onlyProxy))
}

//export forceGC
func forceGC() { core.ForceGC() }

//export updateDns
func updateDns(value *C.char) { core.UpdateDns(takeString(value)) }

//export resetNetwork
func resetNetwork() { core.ResetNetwork() }
