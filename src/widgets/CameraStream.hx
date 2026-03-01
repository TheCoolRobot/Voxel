package widgets;

import js.html.Element;
import js.html.ImageElement;
import core.TopicStore;
import util.EventBus;

class CameraStream extends Widget {
    var img: ImageElement;
    var url: String = "";
    var statusEl: Element;

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "CameraStream");
        title = "Camera";
    }

    override function buildDOM(container: Element): Void {
        container.className += " camera-stream";
        img = cast(js.Browser.document.createElement("img"), ImageElement);
        img.style.cssText = "width:100%;height:100%;object-fit:contain;display:block;";
        img.alt = "Camera feed";

        statusEl = makeEl("div");
        statusEl.style.cssText = "position:absolute;bottom:4px;left:4px;font-size:10px;color:rgba(255,255,255,0.5);pointer-events:none;";

        img.onerror = function(_) { statusEl.textContent = "⚠ Stream error"; };
        img.onload  = function(_) { statusEl.textContent = ""; };

        container.style.position = "relative";
        container.appendChild(img);
        container.appendChild(statusEl);
    }

    override public function configure(props: Dynamic): Void {
        // Camera can be configured via URL directly, or via NT topic that contains a URL
        if (Reflect.hasField(props, "url")) setUrl(props.url);
        super.configure(props);
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        // NT4 camera server publishes URL as string
        if (Std.isOfType(value, String)) setUrl(value);
    }

    function setUrl(newUrl: String): Void {
        if (newUrl == url) return;
        url = newUrl;
        if (url.length > 0) {
            // MJPEG streams: add timestamp to force reload
            img.src = url.indexOf("?") >= 0 ? url : url + "?t=" + Std.string(Date.now().getTime());
            statusEl.textContent = "Connecting...";
        } else {
            img.src = "";
            statusEl.textContent = "No URL configured";
        }
    }

    override public function serialize(): Dynamic {
        var o = super.serialize();
        o.url = url;
        return o;
    }
}
