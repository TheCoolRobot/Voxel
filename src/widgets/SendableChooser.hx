package widgets;

import js.html.Element;
import js.html.SelectElement;
import core.TopicStore;
import util.EventBus;

class SendableChooser extends Widget {
    var activeLabel: Element;
    var selectEl: SelectElement;
    var baseTopic: String = "";
    var activeChoice: String = "";
    var options: Array<String> = [];

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "SendableChooser");
        title = "Chooser";
    }

    override function buildDOM(container: Element): Void {
        container.className += " sendable-chooser";
        activeLabel = makeEl("div", "active-label");
        activeLabel.textContent = "Active: —";
        container.appendChild(activeLabel);

        selectEl = cast(js.Browser.document.createElement("select"), SelectElement);
        selectEl.addEventListener("change", function(_) {
            var chosen = selectEl.value;
            if (baseTopic.length > 0)
                bus.emit("nt:publish", { topic: baseTopic + "/selected", value: chosen, type: "string" });
        });
        container.appendChild(selectEl);
    }

    override public function configure(props: Dynamic): Void {
        if (Reflect.hasField(props, "topic")) {
            baseTopic = props.topic;
            ntTopics = [
                baseTopic + "/active",
                baseTopic + "/options",
                baseTopic + "/selected",
                baseTopic + "/.type"
            ];
            // Subscribe to each
            for (t in ntTopics) {
                var topic = t;
                subscribeTopic(topic, onNTUpdate);
            }
        }
        if (Reflect.hasField(props, "title")) title = props.title;
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        if (StringTools.endsWith(topic, "/active")) {
            activeChoice = Std.string(value);
            if (activeLabel != null) activeLabel.textContent = "Active: " + activeChoice;
        } else if (StringTools.endsWith(topic, "/options")) {
            if (Std.isOfType(value, Array)) {
                options = cast value;
                rebuildOptions();
            }
        }
    }

    function rebuildOptions(): Void {
        if (selectEl == null) return;
        selectEl.innerHTML = "";
        for (opt in options) {
            var optEl = js.Browser.document.createElement("option");
            optEl.textContent = opt;
            cast(optEl, js.html.OptionElement).value = opt;
            selectEl.appendChild(optEl);
        }
    }

    override public function serialize(): Dynamic {
        return { title: title, topic: baseTopic };
    }
}
