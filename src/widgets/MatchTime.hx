package widgets;

import js.html.Element;
import core.TopicStore;
import util.EventBus;

class MatchTime extends Widget {
    var timeEl: Element;
    var phaseEl: Element;
    var warningThreshold: Float = 30.0;
    var dangerThreshold: Float = 10.0;
    var currentTime: Float = -1.0;

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "MatchTime");
        title = "Match Time";
    }

    override function buildDOM(container: Element): Void {
        container.className += " match-time";
        timeEl = makeEl("div", "time-value");
        timeEl.textContent = "--:--";
        container.appendChild(timeEl);

        phaseEl = makeEl("div", "phase");
        phaseEl.textContent = "IDLE";
        container.appendChild(phaseEl);

        // Also subscribe to match phase
        subscribeTopic("/FMSInfo/MatchType", function(_, v) {
            phaseEl.textContent = Std.string(v);
        });
        subscribeTopic("/DriverStation/MatchTime", function(_, v) {
            updateTime(v);
        });
    }

    override public function configure(props: Dynamic): Void {
        super.configure(props);
        if (Reflect.hasField(props, "warningThreshold")) warningThreshold = props.warningThreshold;
        if (Reflect.hasField(props, "dangerThreshold"))  dangerThreshold  = props.dangerThreshold;
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        updateTime(value);
    }

    function updateTime(value: Dynamic): Void {
        currentTime = value;
        if (timeEl == null) return;
        var t: Float = value;
        if (t < 0) {
            timeEl.textContent = "--:--";
            timeEl.className = "time-value";
            return;
        }
        var mins = Std.int(t / 60);
        var secs = Std.int(t % 60);
        timeEl.textContent = (mins > 0 ? mins + ":" : "") +
            (secs < 10 ? "0" : "") + Std.string(secs);

        // Color thresholds
        timeEl.className = "time-value";
        if (t <= dangerThreshold)      timeEl.classList.add("danger");
        else if (t <= warningThreshold) timeEl.classList.add("warning");
    }

    override public function serialize(): Dynamic {
        var o = super.serialize();
        o.warningThreshold = warningThreshold;
        o.dangerThreshold  = dangerThreshold;
        return o;
    }
}
