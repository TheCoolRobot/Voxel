package widgets;

import js.html.Element;
import core.TopicStore;
import util.EventBus;

class NumberDisplay extends Widget {
    var decimals: Int = 2;
    var unit: String = "";
    var valueEl: Element;
    var unitEl: Element;

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "NumberDisplay");
        title = "Number";
    }

    override function buildDOM(container: Element): Void {
        container.className += " number-display";
        valueEl = makeEl("div", "value");
        valueEl.textContent = "—";
        container.appendChild(valueEl);
        unitEl = makeEl("div", "unit");
        unitEl.textContent = unit;
        container.appendChild(unitEl);
    }

    override public function configure(props: Dynamic): Void {
        super.configure(props);
        if (Reflect.hasField(props, "decimals")) decimals = props.decimals;
        if (Reflect.hasField(props, "unit"))     unit = props.unit;
        if (unitEl != null) unitEl.textContent = unit;
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        if (valueEl == null) return;
        var n: Float = value;
        valueEl.textContent = formatNum(n);
    }

    function formatNum(n: Float): String {
        if (!Math.isFinite(n)) return "—";
        var factor = Math.pow(10, decimals);
        return Std.string(Math.round(n * factor) / factor);
    }

    override public function serialize(): Dynamic {
        var o = super.serialize();
        o.decimals = decimals;
        o.unit = unit;
        return o;
    }
}
