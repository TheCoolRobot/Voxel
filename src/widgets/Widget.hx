package widgets;

import js.html.Element;
import core.TopicStore;
import util.EventBus;

/**
 * Base class for all dashboard widgets.
 */
class Widget {
    public var widgetType(default, null): String;
    public var title: String = "";
    public var ntTopics: Array<String> = [];

    var store: TopicStore;
    var bus: EventBus;
    var container: Element;
    var unsubFns: Array<Void->Void> = [];

    public function new(store: TopicStore, bus: EventBus, type: String) {
        this.store = store;
        this.bus = bus;
        this.widgetType = type;
    }

    /** Called by WidgetTile to attach widget DOM into the tile content area. */
    public function mount(container: Element): Void {
        this.container = container;
        buildDOM(container);
    }

    /** Override in subclasses to build widget-specific DOM. */
    function buildDOM(container: Element): Void {}

    /** Apply configuration from a props object. Call super first. */
    public function configure(props: Dynamic): Void {
        if (Reflect.hasField(props, "title"))  title = props.title;
        if (Reflect.hasField(props, "topic")) {
            ntTopics = [props.topic];
            subscribeAll();
        }
        if (Reflect.hasField(props, "topics")) {
            ntTopics = props.topics;
            subscribeAll();
        }
    }

    /** Serialize configuration to JSON-safe object. */
    public function serialize(): Dynamic {
        var obj: Dynamic = { title: title };
        if (ntTopics.length == 1) Reflect.setField(obj, "topic", ntTopics[0]);
        else if (ntTopics.length > 1) Reflect.setField(obj, "topics", ntTopics);
        return obj;
    }

    /** Called when an NT topic updates. Override to handle. */
    public function onNTUpdate(topic: String, value: Dynamic): Void {}

    /** Called when the tile is resized. Override to re-render canvas etc. */
    public function onResize(): Void {}

    /** Cleanup: unsubscribe from all topics. */
    public function destroy(): Void {
        for (fn in unsubFns) fn();
        unsubFns = [];
    }

    // ─── Subscription helpers ─────────────────────────────────────────────────

    function subscribeAll(): Void {
        for (fn in unsubFns) fn();
        unsubFns = [];
        for (topic in ntTopics) {
            if (topic.length == 0) continue;
            var unsub = store.subscribe(topic, onNTUpdate);
            unsubFns.push(unsub);
        }
    }

    function subscribeTopic(topic: String, cb: String->Dynamic->Void): Void {
        if (topic.length == 0) return;
        var unsub = store.subscribe(topic, cb);
        unsubFns.push(unsub);
    }

    function subscribePrefix(prefix: String, cb: String->Dynamic->Void): Void {
        var unsub = store.subscribePrefix(prefix, cb);
        unsubFns.push(unsub);
    }

    function publish(topic: String, value: Dynamic, type: String = "string"): Void {
        bus.emit("nt:publish", { topic: topic, value: value, type: type });
    }

    // ─── DOM helpers ──────────────────────────────────────────────────────────

    function makeEl(tag: String, cls: String = ""): Element {
        var el = js.Browser.document.createElement(tag);
        if (cls.length > 0) el.className = cls;
        return el;
    }

    function makeCanvas(): js.html.CanvasElement {
        var c = cast(js.Browser.document.createElement("canvas"), js.html.CanvasElement);
        c.style.cssText = "width:100%;height:100%;display:block;";
        return c;
    }
}
