package widgets;

import js.html.Element;
import core.TopicStore;
import util.EventBus;

class BooleanBox extends Widget {
    var trueColor: String = "#00e676";
    var falseColor: String = "#ff5252";
    var trueLabel: String = "TRUE";
    var falseLabel: String = "FALSE";
    var indicator: Element;

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "BooleanBox");
        title = "Boolean";
    }

    override function buildDOM(container: Element): Void {
        container.className += " boolean-box";
        indicator = makeEl("div", "bool-indicator");
        indicator.textContent = falseLabel;
        container.appendChild(indicator);
    }

    override public function configure(props: Dynamic): Void {
        super.configure(props);
        if (Reflect.hasField(props, "trueColor"))  trueColor = props.trueColor;
        if (Reflect.hasField(props, "falseColor")) falseColor = props.falseColor;
        if (Reflect.hasField(props, "trueLabel"))  trueLabel = props.trueLabel;
        if (Reflect.hasField(props, "falseLabel")) falseLabel = props.falseLabel;
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        if (indicator == null) return;
        var b: Bool = value == true || value == 1 || value == "true";
        indicator.textContent = b ? trueLabel : falseLabel;
        indicator.style.background = b ? trueColor : falseColor;
        if (b) indicator.classList.add("true");
        else   indicator.classList.remove("true");
    }

    override public function serialize(): Dynamic {
        var o = super.serialize();
        o.trueColor = trueColor; o.falseColor = falseColor;
        o.trueLabel = trueLabel; o.falseLabel = falseLabel;
        return o;
    }
}
