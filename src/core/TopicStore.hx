package core;

import util.EventBus;

typedef TopicEntry = {
    var id: Int;
    var type: String;
    var value: Dynamic;
    var timestamp: Float;
    var properties: Dynamic;
}

/**
 * Local cache of NT4 topics + values.
 * Notifies subscribers via EventBus on value change.
 */
class TopicStore {
    var bus: EventBus;
    var topics: Map<String, TopicEntry>;       // name → entry
    var idToName: Map<Int, String>;             // id → name
    var subscriptions: Map<String, Array<String->Dynamic->Void>>; // name → callbacks
    var prefixSubs: Map<String, Array<String->Dynamic->Void>>;    // prefix → callbacks

    // NT subscriptions we've sent (to deduplicate)
    var subscribedTopics: Map<String, Bool>;
    var subscribedPrefixes: Map<String, Bool>;

    public function new(bus: EventBus) {
        this.bus = bus;
        topics = new Map();
        idToName = new Map();
        subscriptions = new Map();
        prefixSubs = new Map();
        subscribedTopics = new Map();
        subscribedPrefixes = new Map();
    }

    // ─── Called by NT4Client ──────────────────────────────────────────────────

    public function announce(name: String, id: Int, type: String, properties: Dynamic): Void {
        if (!topics.exists(name)) {
            topics[name] = { id: id, type: type, value: null, timestamp: 0.0, properties: properties };
        } else {
            topics[name].id = id;
            topics[name].type = type;
            topics[name].properties = properties;
        }
        idToName[id] = name;
    }

    public function unannounce(name: String, id: Int): Void {
        topics.remove(name);
        idToName.remove(id);
    }

    public function updateValue(id: Int, timestamp: Float, value: Dynamic): Void {
        var name = idToName[id];
        if (name == null) return;
        var entry = topics[name];
        if (entry == null) return;
        entry.value = value;
        entry.timestamp = timestamp;

        // Notify exact subscribers
        if (subscriptions.exists(name)) {
            for (cb in subscriptions[name].copy()) cb(name, value);
        }

        // Notify prefix subscribers
        for (prefix => cbs in prefixSubs) {
            if (StringTools.startsWith(name, prefix)) {
                for (cb in cbs.copy()) cb(name, value);
            }
        }

        bus.emit("nt:value", { topic: name, value: value, timestamp: timestamp });
    }

    public function updateValueByName(name: String, timestamp: Float, value: Dynamic): Void {
        var entry = topics[name];
        if (entry == null) {
            topics[name] = { id: -1, type: "unknown", value: value, timestamp: timestamp, properties: {} };
        } else {
            entry.value = value;
            entry.timestamp = timestamp;
        }

        if (subscriptions.exists(name)) {
            for (cb in subscriptions[name].copy()) cb(name, value);
        }

        bus.emit("nt:value", { topic: name, value: value, timestamp: timestamp });
    }

    // ─── Widget API ──────────────────────────────────────────────────────────

    public function get(name: String): Dynamic {
        var e = topics[name];
        return e != null ? e.value : null;
    }

    public function getEntry(name: String): Null<TopicEntry> {
        return topics[name];
    }

    /** Subscribe to exact topic. Returns unsubscribe function. */
    public function subscribe(name: String, cb: String->Dynamic->Void): Void->Void {
        if (!subscriptions.exists(name)) subscriptions[name] = [];
        subscriptions[name].push(cb);

        // Fire immediately if we have a value
        var e = topics[name];
        if (e != null && e.value != null) cb(name, e.value);

        // Request NT subscription (signals NT4Client via bus)
        if (!subscribedTopics[name]) {
            subscribedTopics[name] = true;
            bus.emit("store:subscribe", { topic: name, prefix: false });
        }

        return function() {
            if (subscriptions.exists(name))
                subscriptions[name] = subscriptions[name].filter(f -> f != cb);
        };
    }

    /** Subscribe to all topics under a prefix. */
    public function subscribePrefix(prefix: String, cb: String->Dynamic->Void): Void->Void {
        if (!prefixSubs.exists(prefix)) prefixSubs[prefix] = [];
        prefixSubs[prefix].push(cb);

        // Fire existing values
        for (name => entry in topics) {
            if (StringTools.startsWith(name, prefix) && entry.value != null)
                cb(name, entry.value);
        }

        if (!subscribedPrefixes[prefix]) {
            subscribedPrefixes[prefix] = true;
            bus.emit("store:subscribe", { topic: prefix, prefix: true });
        }

        return function() {
            if (prefixSubs.exists(prefix))
                prefixSubs[prefix] = prefixSubs[prefix].filter(f -> f != cb);
        };
    }

    public function getAllNames(): Array<String> {
        return [for (k in topics.keys()) k];
    }

    public function clear(): Void {
        topics.clear();
        idToName.clear();
        subscribedTopics.clear();
        subscribedPrefixes.clear();
    }
}
