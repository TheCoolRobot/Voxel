package util;

/**
 * Simple typed pub/sub event bus (singleton).
 */
class EventBus {
    static var _instance: EventBus;
    public static var instance(get, never): EventBus;
    static function get_instance(): EventBus {
        if (_instance == null) _instance = new EventBus();
        return _instance;
    }

    var listeners: Map<String, Array<Dynamic->Void>>;

    public function new() {
        listeners = new Map();
    }

    public function on(event: String, cb: Dynamic->Void): Void {
        if (!listeners.exists(event)) listeners[event] = [];
        listeners[event].push(cb);
    }

    public function off(event: String, cb: Dynamic->Void): Void {
        if (!listeners.exists(event)) return;
        listeners[event] = listeners[event].filter(f -> f != cb);
    }

    public function emit(event: String, data: Dynamic = null): Void {
        if (!listeners.exists(event)) return;
        // copy to avoid modification during iteration
        var cbs = listeners[event].copy();
        for (cb in cbs) cb(data);
    }

    /** Subscribe once — auto-removes after first call. */
    public function once(event: String, cb: Dynamic->Void): Void {
        var wrapper: Dynamic->Void = null;
        wrapper = function(d) {
            off(event, wrapper);
            cb(d);
        };
        on(event, wrapper);
    }
}
