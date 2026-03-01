package widgets;

import js.html.Element;
import core.TopicStore;
import util.EventBus;

class TextDisplay extends Widget {
    var wordWrap: Bool = true;
    var valueEl: Element;

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "TextDisplay");
        title = "Text";
    }

    override function buildDOM(container: Element): Void {
        container.className += " text-display";
        valueEl = makeEl("div", "value");
        if (!wordWrap) {
            valueEl.style.whiteSpace = "nowrap";
            valueEl.style.overflow = "hidden";
            valueEl.style.textOverflow = "ellipsis";
        }
        container.appendChild(valueEl);
    }

    override public function configure(props: Dynamic): Void {
        super.configure(props);
        if (Reflect.hasField(props, "wordWrap")) wordWrap = props.wordWrap;
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        if (valueEl != null) valueEl.textContent = Std.string(value);
    }

    override public function serialize(): Dynamic {
        var o = super.serialize();
        o.wordWrap = wordWrap;
        return o;
    }
}
