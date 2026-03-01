package widgets;

import js.html.Element;
import core.TopicStore;
import util.EventBus;

class ToggleButton extends Widget {
    var state: Bool = false;
    var btn: Element;
    var ntTopic: String = "";

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "ToggleButton");
        title = "Toggle";
    }

    override function buildDOM(container: Element): Void {
        container.className += " toggle-button";
        btn = makeEl("button", "toggle-btn");
        btn.textContent = "OFF";
        btn.addEventListener("click", function(_) {
            state = !state;
            updateDisplay();
            if (ntTopic.length > 0)
                bus.emit("nt:publish", { topic: ntTopic, value: state, type: "boolean" });
        });
        container.appendChild(btn);
    }

    override public function configure(props: Dynamic): Void {
        super.configure(props);
        if (ntTopics.length > 0) ntTopic = ntTopics[0];
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        state = value == true || value == 1;
        updateDisplay();
    }

    function updateDisplay(): Void {
        if (btn == null) return;
        btn.textContent = state ? "ON" : "OFF";
        if (state) btn.classList.add("on");
        else        btn.classList.remove("on");
    }
}
