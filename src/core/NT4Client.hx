package core;

import haxe.io.Bytes;
import js.html.WebSocket;
import js.Browser;
import util.EventBus;

typedef NTSubscription = {
    var uid: Int;
    var topics: Array<String>;
    var prefix: Bool;
    var options: Dynamic;
}

/**
 * NT4 WebSocket client.
 * Text frames: JSON control messages.
 * Binary frames: MessagePack data updates.
 */
class NT4Client {
    static inline var NT_SUBPROTOCOL = "networktables.first.wpi.edu";
    static inline var MIN_BACKOFF_MS = 500;
    static inline var MAX_BACKOFF_MS = 30000;

    var store: TopicStore;
    var bus: EventBus;
    var ws: WebSocket;
    var host: String;
    var port: Int;
    var connected: Bool = false;
    var backoffMs: Float = MIN_BACKOFF_MS;
    var reconnectTimer: Dynamic;
    var identity: String;
    var nextSubUid: Int = 1;
    var pendingSubs: Array<NTSubscription> = [];
    var activeSubs: Array<NTSubscription> = [];

    // Publish tracking
    var nextPubUid: Int = 1;
    var publishedTopics: Map<String, Int> = new Map(); // name → uid

    // Client/server time sync
    var serverTimeOffset: Float = 0.0; // serverTimeUs - clientTimeUs

    public function new(store: TopicStore, bus: EventBus) {
        this.store = store;
        this.bus = bus;
        identity = "frc-dashboard-" + Std.string(Std.random(9999));

        // Listen for subscription requests from TopicStore
        bus.on("store:subscribe", function(data: Dynamic) {
            addSubscription(data.topic, data.prefix);
        });
    }

    // ─── Connection management ────────────────────────────────────────────────

    public function connect(host: String, port: Int = 5810): Void {
        this.host = host;
        this.port = port;
        if (reconnectTimer != null) {
            js.Browser.window.clearTimeout(reconnectTimer);
            reconnectTimer = null;
        }
        doConnect();
    }

    public function disconnect(): Void {
        host = null;
        if (reconnectTimer != null) {
            js.Browser.window.clearTimeout(reconnectTimer);
            reconnectTimer = null;
        }
        if (ws != null) {
            ws.onclose = null;
            ws.close();
            ws = null;
        }
        connected = false;
        bus.emit("nt:disconnected", null);
    }

    public function isConnected(): Bool return connected;

    function doConnect(): Void {
        if (host == null) return;
        var url = 'ws://${host}:${port}/nt/${identity}';
        try {
            ws = new WebSocket(url, NT_SUBPROTOCOL);
            ws.binaryType = cast "arraybuffer";
            ws.onopen = onOpen;
            ws.onclose = onClose;
            ws.onerror = onError;
            ws.onmessage = onMessage;
        } catch (e: Dynamic) {
            trace("NT4: WebSocket creation failed: " + e);
            scheduleReconnect();
        }
    }

    function onOpen(_: Dynamic): Void {
        connected = true;
        backoffMs = MIN_BACKOFF_MS;
        bus.emit("nt:connected", null);
        trace("NT4: connected to " + host);

        // Re-subscribe to all topics
        for (sub in pendingSubs) activeSubs.push(sub);
        pendingSubs = [];
        for (sub in activeSubs) {
            sendSubscribe(sub);
        }

        // Send timestamp sync
        sendTimestampSync();
    }

    function onClose(_: Dynamic): Void {
        connected = false;
        ws = null;
        store.clear();
        bus.emit("nt:disconnected", null);
        if (host != null) scheduleReconnect();
    }

    function onError(_: Dynamic): Void {
        // close will follow
    }

    function scheduleReconnect(): Void {
        reconnectTimer = js.Browser.window.setTimeout(function() {
            reconnectTimer = null;
            doConnect();
        }, Std.int(backoffMs));
        backoffMs = Math.min(backoffMs * 2, MAX_BACKOFF_MS);
    }

    // ─── Message handling ─────────────────────────────────────────────────────

    function onMessage(evt: Dynamic): Void {
        var data: Dynamic = evt.data;

        if (Std.isOfType(data, String)) {
            // Text frame: JSON array of messages
            handleTextFrame(data);
        } else {
            // Binary frame: MessagePack
            handleBinaryFrame(data);
        }
    }

    function handleTextFrame(json: String): Void {
        try {
            var msgs: Array<Dynamic> = haxe.Json.parse(json);
            for (msg in msgs) {
                var method: String = msg.method;
                var params: Dynamic = msg.params;
                switch (method) {
                    case "announce":
                        store.announce(params.name, params.id, params.type, params.properties != null ? params.properties : {});
                    case "unannounce":
                        store.unannounce(params.name, params.id);
                    case "properties":
                        // property update — update store entry
                        var e = store.getEntry(params.name);
                        if (e != null) e.properties = params.update;
                    default:
                        // ignore unknown
                }
            }
        } catch (e: Dynamic) {
            trace("NT4: JSON parse error: " + e);
        }
    }

    function handleBinaryFrame(buffer: Dynamic): Void {
        var bytes = Bytes.ofData(buffer);
        try {
            var arr: Array<Dynamic> = MsgPack.decode(bytes);
            if (arr == null || arr.length < 4) return;
            var topicId: Int = arr[0];
            var timestampUs: Float = arr[1];
            var typeId: Int = arr[2];
            var value: Dynamic = arr[3];

            if (topicId == -1) {
                // Timestamp sync: [−1, clientTime, −1, serverTime]
                serverTimeOffset = value - timestampUs;
            } else {
                store.updateValue(topicId, timestampUs + serverTimeOffset, value);
            }
        } catch (e: Dynamic) {
            trace("NT4: MsgPack decode error: " + e);
        }
    }

    // ─── Subscriptions ────────────────────────────────────────────────────────

    function addSubscription(topic: String, prefix: Bool): Void {
        var sub: NTSubscription = {
            uid: nextSubUid++,
            topics: [topic],
            prefix: prefix,
            options: { periodic: 0.1, all: false, topicsonly: false, prefix: prefix }
        };
        if (connected) {
            activeSubs.push(sub);
            sendSubscribe(sub);
        } else {
            pendingSubs.push(sub);
        }
    }

    function sendSubscribe(sub: NTSubscription): Void {
        var msg = [{
            method: "subscribe",
            params: {
                topics: sub.topics,
                subuid: sub.uid,
                options: sub.options
            }
        }];
        sendText(haxe.Json.stringify(msg));
    }

    // ─── Publishing ───────────────────────────────────────────────────────────

    /**
     * Publish a value to a NT topic.
     * Announces the topic if needed, then sends a binary data frame.
     */
    public function publish(topic: String, value: Dynamic, type: String = "string"): Void {
        if (!connected) return;

        var uid = publishedTopics[topic];
        if (uid == null) {
            uid = nextPubUid++;
            publishedTopics[topic] = uid;
            var announce = [{
                method: "publish",
                params: { name: topic, pubuid: uid, type: type, properties: {} }
            }];
            sendText(haxe.Json.stringify(announce));
        }

        // Binary frame: [topicId, timestamp, typeId, value]
        var typeId = ntTypeId(type);
        var clientTs = clientTimeUs();
        var arr: Array<Dynamic> = [uid, clientTs, typeId, value];
        var bytes = MsgPack.encode(arr);
        sendBinary(bytes);
    }

    public function unpublish(topic: String): Void {
        var uid = publishedTopics[topic];
        if (uid == null || !connected) return;
        publishedTopics.remove(topic);
        var msg = [{ method: "unpublish", params: { name: topic, pubuid: uid } }];
        sendText(haxe.Json.stringify(msg));
    }

    // ─── Helpers ─────────────────────────────────────────────────────────────

    function sendText(s: String): Void {
        if (ws != null && ws.readyState == WebSocket.OPEN)
            ws.send(s);
    }

    function sendBinary(b: Bytes): Void {
        if (ws != null && ws.readyState == WebSocket.OPEN)
            ws.send(b.getData());
    }

    function sendTimestampSync(): Void {
        var t = clientTimeUs();
        var arr: Array<Dynamic> = [-1, t, -1, 0];
        sendBinary(MsgPack.encode(arr));
    }

    function clientTimeUs(): Float {
        return js.Browser.window.performance.now() * 1000.0;
    }

    static function ntTypeId(type: String): Int {
        return switch (type) {
            case "boolean": 0;
            case "double":  1;
            case "int":     2;
            case "float":   3;
            case "string":  4;
            case "json":    4;
            case "raw":     5;
            case "boolean[]": 16;
            case "double[]":  17;
            case "int[]":     18;
            case "float[]":   19;
            case "string[]":  20;
            default: 4;
        };
    }
}
