import JavaScriptKit
import JavaScriptEventLoop
import JavaScriptKitExtensions

// Required for async/await and JSPromise interop
JavaScriptEventLoop.installGlobalExecutor()

// Keep the closure alive for the full lifetime of the WASM module
nonisolated(unsafe) var _convertClosure: JSClosure?

_convertClosure = JSClosure { args -> JSValue in
    guard let jsonStr = args.first?.string else {
        let err = JSObject()
        err.error = "Expected a JSON string as the first argument"
        return err.jsValue
    }

    do {
        let kv = try FigmaMapper.convert(json: jsonStr)
        let result = JSObject()
        result.kv = kv
        return result.jsValue
    } catch {
        let result = JSObject()
        result.error = "\(error)"
        return result.jsValue
    }
}

// Expose on globalThis.figma2kv.convert so index.ts can call it
// after runApplication() has initialised the WASM reactor
let api = JSObject()
api.convert = _convertClosure!.jsValue
JSObject.global.figma2kv = api.jsValue
