#include "napi/native_api.h"
#include "bridge.h"
#include "libclash.h"
#include <cstring>
#include <cstdlib>
#include <future>

enum class InterfaceType {
    Invoke,
    Tun,
};

struct TunInterface {
    InterfaceType type = InterfaceType::Tun;
    napi_threadsafe_function protect;
    napi_threadsafe_function resolveUid;
    napi_threadsafe_function resolvePackage;
};

struct InvokeInterface {
    InterfaceType type = InterfaceType::Invoke;
    napi_threadsafe_function onResult;
};

struct ResolveUidCall {
    int protocol;
    const char *source;
    const char *target;
    std::promise<int> promise;
};

struct ResolvePackageCall {
    int uid;
    std::promise<char*> promise;
};

struct ProtectCall {
    int fd;
    std::promise<bool> promise;
};

struct StopTunWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
};


static char *GetValueStringUtf8(napi_env env, napi_value value) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) return nullptr;
    char *result = static_cast<char*>(malloc(length + 1));
    if (result == nullptr) return nullptr;
    result[0] = '\0';
    napi_get_value_string_utf8(env, value, result, length + 1, &length);
    return result;
}

static int GetValueInt32(napi_env env, napi_value value) {
    int result = 0;
    napi_get_value_int32(env, value, &result);
    return result;
}

static bool GetValueBool(napi_env env, napi_value value) {
    bool result = false;
    napi_get_value_bool(env, value, &result);
    return result;
}

static napi_value CreateValueStringUtf8(napi_env env, const char *data) {
    napi_value result = nullptr;
    napi_create_string_utf8(env, data == nullptr ? "" : data, NAPI_AUTO_LENGTH, &result);
    return result;
}

static napi_value CreateValueInt32(napi_env env, int data) {
    napi_value result = nullptr;
    napi_create_int32(env, data, &result);
    return result;
}


void InvokeActionCallJsCallback(napi_env env, napi_value callback, void* context, void* data){
    if (env == nullptr || callback == nullptr) {
        free(data);
        return;
    }
    napi_value global = nullptr;
    napi_get_global(env, &global);
    napi_value argv = CreateValueStringUtf8(env, reinterpret_cast<char*>(data));
    napi_value result = nullptr;
    napi_call_function(env, global, callback, 1, &argv, &result);
    free(data);
}

static napi_value CompleteProtect(napi_env env, napi_callback_info info, bool protectedSocket) {
    void *data = nullptr;
    napi_get_cb_info(env, info, nullptr, nullptr, nullptr, &data);
    static_cast<ProtectCall*>(data)->promise.set_value(protectedSocket);
    return nullptr;
}

static napi_value ProtectSucceeded(napi_env env, napi_callback_info info) {
    return CompleteProtect(env, info, true);
}

static napi_value ProtectFailed(napi_env env, napi_callback_info info) {
    return CompleteProtect(env, info, false);
}

void ProtectCallJsCallback(napi_env env, napi_value callback, void *context, void *data) {
    ProtectCall *call = static_cast<ProtectCall*>(data);
    if (env == nullptr || callback == nullptr) {
        call->promise.set_value(false);
        return;
    }
    napi_value global = nullptr;
    napi_get_global(env, &global);
    napi_value argv = CreateValueInt32(env, call->fd);
    napi_value result = nullptr;
    if (napi_call_function(env, global, callback, 1, &argv, &result) != napi_ok) {
        napi_value exception = nullptr;
        napi_get_and_clear_last_exception(env, &exception);
        call->promise.set_value(false);
        return;
    }
    napi_value then = nullptr;
    napi_get_named_property(env, result, "then", &then);
    napi_value success = nullptr;
    napi_value failure = nullptr;
    napi_create_function(env, "protectSucceeded", NAPI_AUTO_LENGTH, ProtectSucceeded, call, &success);
    napi_create_function(env, "protectFailed", NAPI_AUTO_LENGTH, ProtectFailed, call, &failure);
    napi_value thenArgs[2] = {success, failure};
    napi_value thenResult = nullptr;
    napi_call_function(env, result, then, 2, thenArgs, &thenResult);
}

void ResolveUidCallJsCallback(napi_env env, napi_value callback, void *context, void *data) {
    ResolveUidCall *call = static_cast<ResolveUidCall*>(data);
    if (env == nullptr || callback == nullptr) {
        call->promise.set_value(-1);
        return;
    }
    napi_value global = nullptr;
    napi_get_global(env, &global);
    napi_value argv[3] = {CreateValueInt32(env, call->protocol), CreateValueStringUtf8(env, call->source), CreateValueStringUtf8(env, call->target)};
    napi_value result = nullptr;
    if (napi_call_function(env, global, callback, 3, argv, &result) != napi_ok) {
        napi_value exception = nullptr;
        napi_get_and_clear_last_exception(env, &exception);
        call->promise.set_value(-1);
        return;
    }
    int uid = -1;
    napi_get_value_int32(env, result, &uid);
    call->promise.set_value(uid);
}

void ResolvePackageCallJsCallback(napi_env env, napi_value callback, void *context, void *data) {
    ResolvePackageCall *call = static_cast<ResolvePackageCall*>(data);
    if (env == nullptr || callback == nullptr) {
        call->promise.set_value(nullptr);
        return;
    }
    napi_value global = nullptr;
    napi_get_global(env, &global);
    napi_value argv = CreateValueInt32(env, call->uid);
    napi_value result = nullptr;
    if (napi_call_function(env, global, callback, 1, &argv, &result) != napi_ok) {
        napi_value exception = nullptr;
        napi_get_and_clear_last_exception(env, &exception);
        call->promise.set_value(nullptr);
        return;
    }
    call->promise.set_value(GetValueStringUtf8(env, result));
}

static napi_value InvokeMethod(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    InvokeInterface *invokeInterface = new InvokeInterface();
    napi_create_threadsafe_function(env, argv[0], nullptr, CreateValueStringUtf8(env, "onResult"), 0, 1, nullptr, nullptr, nullptr, InvokeActionCallJsCallback, &invokeInterface->onResult);
    invokeMethod(invokeInterface, GetValueStringUtf8(env, argv[1]));
    return nullptr;
}

static napi_value StartTUN(napi_env env, napi_callback_info info) {
    size_t argc = 8;
    napi_value argv[8] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    TunInterface *tunInterface = new TunInterface();
    napi_create_threadsafe_function(env, argv[0], nullptr, CreateValueStringUtf8(env, "protect"), 0, 1, nullptr, nullptr, nullptr, ProtectCallJsCallback, &tunInterface->protect);
    napi_create_threadsafe_function(env, argv[1], nullptr, CreateValueStringUtf8(env, "resolveUid"), 0, 1, nullptr, nullptr, nullptr, ResolveUidCallJsCallback, &tunInterface->resolveUid);
    napi_create_threadsafe_function(env, argv[2], nullptr, CreateValueStringUtf8(env, "resolvePackage"), 0, 1, nullptr, nullptr, nullptr, ResolvePackageCallJsCallback, &tunInterface->resolvePackage);
    const bool started = startTUN(tunInterface, GetValueInt32(env, argv[3]), GetValueStringUtf8(env, argv[4]), GetValueStringUtf8(env, argv[5]), GetValueStringUtf8(env, argv[6]), GetValueStringUtf8(env, argv[7]));
    napi_value result = nullptr;
    napi_get_boolean(env, started, &result);
    return result;
}

static napi_value QuickSetup(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value argv[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    InvokeInterface *invokeInterface = new InvokeInterface();
    napi_create_threadsafe_function(env, argv[0], nullptr, CreateValueStringUtf8(env, "onResult"), 0, 1, nullptr, nullptr, nullptr, InvokeActionCallJsCallback, &invokeInterface->onResult);
    quickSetup(invokeInterface, GetValueStringUtf8(env, argv[1]), GetValueStringUtf8(env, argv[2]));
    return nullptr;
}

static napi_value SetEventListener(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_valuetype type = napi_undefined;
    if (argc > 0) {
        napi_typeof(env, argv[0], &type);
    }
    if (argc == 0 || type == napi_undefined || type == napi_null) {
        setEventListener(nullptr);
        return nullptr;
    }
    InvokeInterface *invokeInterface = new InvokeInterface();
    napi_create_threadsafe_function(env, argv[0], nullptr, CreateValueStringUtf8(env, "onResult"), 0, 1, nullptr, nullptr, nullptr, InvokeActionCallJsCallback, &invokeInterface->onResult);
    setEventListener(invokeInterface);
    return nullptr;
}

static napi_value GetTotalTraffic(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    char *data = getTotalTraffic(GetValueBool(env, argv[0]));
    napi_value result = CreateValueStringUtf8(env, data);
    free(data);
    return result;
}

static napi_value GetTraffic(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    char *data = getTraffic(GetValueBool(env, argv[0]));
    napi_value result = CreateValueStringUtf8(env, data);
    free(data);
    return result;
}

static void ExecuteStopTun(napi_env env, void *data) {
    stopTun();
}

static void CompleteStopTun(napi_env env, napi_status status, void *data) {
    StopTunWork *work = static_cast<StopTunWork*>(data);
    napi_value result = nullptr;
    if (status == napi_ok) {
        napi_get_undefined(env, &result);
        napi_resolve_deferred(env, work->deferred, result);
    } else {
        napi_create_error(env, nullptr, CreateValueStringUtf8(env, "Stop TUN work was cancelled"), &result);
        napi_reject_deferred(env, work->deferred, result);
    }
    napi_delete_async_work(env, work->work);
    delete work;
}

static napi_value StopTun(napi_env env, napi_callback_info info) {
    // Go waits for JS socket callbacks while closing the TUN; keep this JS thread free.
    StopTunWork *work = new StopTunWork();
    napi_value promise = nullptr;
    if (napi_create_promise(env, &work->deferred, &promise) != napi_ok) {
        delete work;
        return nullptr;
    }
    napi_status status = napi_create_async_work(env, nullptr, CreateValueStringUtf8(env, "stopTun"),
                                               ExecuteStopTun, CompleteStopTun, work, &work->work);
    if (status == napi_ok) status = napi_queue_async_work(env, work->work);
    if (status != napi_ok) {
        napi_value error = nullptr;
        napi_create_error(env, nullptr, CreateValueStringUtf8(env, "Unable to schedule Stop TUN"), &error);
        napi_reject_deferred(env, work->deferred, error);
        if (work->work != nullptr) napi_delete_async_work(env, work->work);
        delete work;
    }
    return promise;
}

static napi_value ForceGC(napi_env env, napi_callback_info info) {
    forceGC();
    return nullptr;
}

static napi_value UpdateDns(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    updateDns(GetValueStringUtf8(env, argv[0]));
    return nullptr;
}

static bool call_tun_interface_protect_impl(void *tun_interface, const int fd) {
    TunInterface *tunInterface = static_cast<TunInterface*>(tun_interface);
    ProtectCall call{fd, {}};
    std::future<bool> future = call.promise.get_future();
    if (napi_call_threadsafe_function(tunInterface->protect, &call, napi_tsfn_nonblocking) != napi_ok) return false;
    return future.get();
}

static int call_tun_interface_resolve_uid_impl(void *tun_interface, const int protocol, const char *source, const char *target) {
    TunInterface *tunInterface = static_cast<TunInterface*>(tun_interface);
    ResolveUidCall call{protocol, source, target, {}};
    std::future<int> future = call.promise.get_future();
    if (napi_call_threadsafe_function(tunInterface->resolveUid, &call, napi_tsfn_nonblocking) != napi_ok) return -1;
    return future.get();
}

static char *call_tun_interface_resolve_package_impl(void *tun_interface, const int uid) {
    TunInterface *tunInterface = static_cast<TunInterface*>(tun_interface);
    ResolvePackageCall call{uid, {}};
    std::future<char*> future = call.promise.get_future();
    if (napi_call_threadsafe_function(tunInterface->resolvePackage, &call, napi_tsfn_nonblocking) != napi_ok) return nullptr;
    return future.get();
}

static void call_invoke_interface_result_impl(void *invoke_interface, const char *data) {
    InvokeInterface *invokeInterface = reinterpret_cast<InvokeInterface*>(invoke_interface);
    char *dataCopy = nullptr;
    if (data != nullptr) {
        size_t length = std::strlen(data);
        dataCopy = static_cast<char*>(malloc(length + 1));
        std::memcpy(dataCopy, data, length + 1);
    }
    if (napi_call_threadsafe_function(invokeInterface->onResult, dataCopy, napi_tsfn_nonblocking) != napi_ok) free(dataCopy);
}

static void release_object_impl(void *obj) {
    if (obj == nullptr) {
        return;
    }
    if (*reinterpret_cast<InterfaceType*>(obj) == InterfaceType::Tun) {
        TunInterface *tunInterface = reinterpret_cast<TunInterface*>(obj);
        napi_release_threadsafe_function(tunInterface->protect, napi_tsfn_release);
        napi_release_threadsafe_function(tunInterface->resolveUid, napi_tsfn_release);
        napi_release_threadsafe_function(tunInterface->resolvePackage, napi_tsfn_release);
        delete tunInterface;
        return;
    }
    InvokeInterface *invokeInterface = reinterpret_cast<InvokeInterface*>(obj);
    napi_release_threadsafe_function(invokeInterface->onResult, napi_tsfn_release);
    delete invokeInterface;
}

static void free_string_impl(char *data) {
    free(data);
}


static napi_value ResetNetwork(napi_env env, napi_callback_info info) {
    resetNetwork();
    return nullptr;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "invokeMethod", nullptr, InvokeMethod, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "startTUN", nullptr, StartTUN, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "quickSetup", nullptr, QuickSetup, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setEventListener", nullptr, SetEventListener, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getTotalTraffic", nullptr, GetTotalTraffic, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "getTraffic", nullptr, GetTraffic, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stopTun", nullptr, StopTun, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "forceGC", nullptr, ForceGC, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "updateDns", nullptr, UpdateDns, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "resetNetwork", nullptr, ResetNetwork, nullptr, nullptr, nullptr, napi_default, nullptr }
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    protect_func = &call_tun_interface_protect_impl;
    resolve_uid_func = &call_tun_interface_resolve_uid_impl;
    resolve_package_func = &call_tun_interface_resolve_package_impl;
    result_func = &call_invoke_interface_result_impl;
    release_object_func = &release_object_impl;
    free_string_func = &free_string_impl;

    return exports;
}
EXTERN_C_END

static napi_module coreModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "core",
    .nm_priv = ((void*)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterCoreModule(void)
{
    napi_module_register(&coreModule);
}
