import JavaScriptKit

func makeJSObject(_ entries: [(String, JSValue)]) -> JSObject {
    let object = JSObject()
    for (key, value) in entries {
        object[key] = value
    }
    return object
}

func makeJSValueObject(_ entries: [(String, JSValue)]) -> JSValue {
    .object(makeJSObject(entries))
}

func requireObject(_ value: JSValue, _ message: String) throws(JSException) -> JSObject {
    guard let object = value.object else {
        throw JSException(message: message)
    }
    return object
}

func requireString(_ value: JSValue, _ message: String) throws(JSException) -> String {
    guard let string = value.string else {
        throw JSException(message: message)
    }
    return string
}

func requireFunctionResult(_ value: JSValue, _ message: String) throws(JSException) -> JSObject {
    try requireObject(value, message)
}
