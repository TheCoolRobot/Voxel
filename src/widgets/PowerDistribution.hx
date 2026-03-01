package widgets;

import js.html.Element;
import core.TopicStore;
import util.EventBus;
import util.ColorUtil;
import util.MathUtil;

class PowerDistribution extends Widget {
    var barsContainer: Element;
    var voltageEl: Element;
    var channelEls: Array<{bar: Element, val: Element}> = [];
    var maxCurrent: Float = 40.0;
    var numChannels: Int = 23;
    var baseTopic: String = "";

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "PowerDistribution");
        title = "Power Distribution";
    }

    override function buildDOM(container: Element): Void {
        container.className += " power-distribution";
        container.style.overflow = "auto";

        voltageEl = makeEl("div");
        voltageEl.style.cssText = "font-size:14px;font-weight:700;color:var(--accent-yellow);margin-bottom:8px;";
        voltageEl.textContent = "Voltage: —";
        container.appendChild(voltageEl);

        barsContainer = makeEl("div", "channel-bars");
        container.appendChild(barsContainer);
    }

    override public function configure(props: Dynamic): Void {
        if (Reflect.hasField(props, "topic")) {
            baseTopic = props.topic;
            if (Reflect.hasField(props, "maxCurrent")) maxCurrent = props.maxCurrent;
            ntTopics = [baseTopic];

            // Subscribe to voltage and each channel
            subscribeTopic(baseTopic + "/Voltage", function(_, v) {
                if (voltageEl != null)
                    voltageEl.textContent = "Voltage: " + (Math.round(cast(v, Float) * 100) / 100) + " V";
            });

            // Subscribe to channel currents
            for (i in 0...numChannels) {
                var ch = i;
                subscribeTopic(baseTopic + "/Chan" + i, function(_, v) {
                    updateChannel(ch, v);
                });
            }

            buildChannelBars();
        }
        if (Reflect.hasField(props, "title")) title = props.title;
    }

    function buildChannelBars(): Void {
        barsContainer.innerHTML = "";
        channelEls = [];
        for (i in 0...numChannels) {
            var row = makeEl("div", "channel-row");
            var lbl = makeEl("div", "ch-label");
            lbl.textContent = Std.string(i);
            var barBg = makeEl("div", "ch-bar-bg");
            var bar = makeEl("div", "ch-bar");
            bar.style.width = "0%";
            barBg.appendChild(bar);
            var val = makeEl("div", "ch-val");
            val.textContent = "0.0A";
            row.appendChild(lbl);
            row.appendChild(barBg);
            row.appendChild(val);
            barsContainer.appendChild(row);
            channelEls.push({ bar: bar, val: val });
        }
    }

    function updateChannel(ch: Int, current: Dynamic): Void {
        if (ch >= channelEls.length) return;
        var els = channelEls[ch];
        var a: Float = current;
        var pct = MathUtil.clamp(a / maxCurrent * 100.0, 0.0, 100.0);
        var t   = pct / 100.0;
        els.bar.style.width = pct + "%";
        els.bar.style.background = ColorUtil.trafficLight(t);
        els.val.textContent = (Math.round(a * 10) / 10) + "A";
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {}

    override public function serialize(): Dynamic {
        return { title: title, topic: baseTopic, maxCurrent: maxCurrent };
    }
}
