package widgets;

import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.Element;
import core.TopicStore;
import util.EventBus;
import util.MathUtil;
import util.ColorUtil;

class Gauge extends Widget {
    var canvas: CanvasElement;
    var ctx: CanvasRenderingContext2D;
    var minVal: Float = 0.0;
    var maxVal: Float = 100.0;
    var value: Float = 0.0;
    var unit: String = "";
    var zones: Array<{min: Float, max: Float, color: String}> = [];

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "Gauge");
        title = "Gauge";
        zones = [
            { min: 0.0,  max: 0.6, color: "#00e676" },
            { min: 0.6,  max: 0.85, color: "#ffd740" },
            { min: 0.85, max: 1.0,  color: "#ff5252" }
        ];
    }

    override function buildDOM(container: Element): Void {
        container.className += " gauge";
        canvas = makeCanvas();
        container.appendChild(canvas);
    }

    override public function configure(props: Dynamic): Void {
        super.configure(props);
        if (Reflect.hasField(props, "min"))  minVal = props.min;
        if (Reflect.hasField(props, "max"))  maxVal = props.max;
        if (Reflect.hasField(props, "unit")) unit = props.unit;
        render();
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        this.value = value;
        render();
    }

    override public function onResize(): Void {
        if (canvas != null && container != null) {
            canvas.width = Std.int(container.clientWidth);
            canvas.height = Std.int(container.clientHeight);
            render();
        }
    }

    function render(): Void {
        if (canvas == null) return;
        var w = canvas.clientWidth;
        var h = canvas.clientHeight;
        if (canvas.width != w || canvas.height != h) { canvas.width = w; canvas.height = h; }
        if (w == 0 || h == 0) return;
        if (ctx == null) ctx = canvas.getContext2d();

        ctx.clearRect(0, 0, w, h);

        var cx = w / 2;
        var cy = h * 0.65;
        var r  = Math.min(w * 0.42, h * 0.62);
        var startA = Math.PI * 0.75;
        var endA   = Math.PI * 2.25;
        var arcW   = r * 0.18;

        // Background arc
        ctx.beginPath();
        ctx.arc(cx, cy, r, startA, endA);
        ctx.strokeStyle = "rgba(255,255,255,0.08)";
        ctx.lineWidth = arcW;
        ctx.lineCap = "round";
        ctx.stroke();

        // Zone arcs
        for (zone in zones) {
            var za = startA + zone.min * (endA - startA);
            var zb = startA + zone.max * (endA - startA);
            ctx.beginPath();
            ctx.arc(cx, cy, r, za, zb);
            ctx.strokeStyle = zone.color + "44";
            ctx.lineWidth = arcW;
            ctx.lineCap = "butt";
            ctx.stroke();
        }

        // Value arc
        var t = MathUtil.clamp((value - minVal) / (maxVal - minVal), 0.0, 1.0);
        var valAngle = startA + t * (endA - startA);
        ctx.beginPath();
        ctx.arc(cx, cy, r, startA, valAngle);
        ctx.strokeStyle = getZoneColor(t);
        ctx.lineWidth = arcW;
        ctx.lineCap = "round";
        ctx.stroke();

        // Needle dot
        var nx = cx + r * Math.cos(valAngle);
        var ny = cy + r * Math.sin(valAngle);
        ctx.beginPath();
        ctx.arc(nx, ny, arcW * 0.6, 0, Math.PI * 2);
        ctx.fillStyle = "#ffffff";
        ctx.fill();

        // Value text
        ctx.textAlign = "center";
        ctx.fillStyle = "#e0e0f0";
        ctx.font = "bold " + Std.int(r * 0.28) + "px monospace";
        ctx.fillText(formatVal(value), cx, cy + r * 0.12);

        // Min/Max labels
        ctx.font = "10px sans-serif";
        ctx.fillStyle = "rgba(144,144,176,0.7)";
        ctx.textAlign = "left";
        ctx.fillText(Std.string(minVal), cx - r * 0.9, cy + r * 0.5);
        ctx.textAlign = "right";
        ctx.fillText(Std.string(maxVal) + (unit.length > 0 ? " " + unit : ""), cx + r * 0.9, cy + r * 0.5);
    }

    function getZoneColor(t: Float): String {
        for (z in zones) {
            if (t >= z.min && t <= z.max) return z.color;
        }
        return "#4a9eff";
    }

    function formatVal(v: Float): String {
        if (Math.abs(v) >= 1000) return Std.string(Math.round(v));
        return Std.string(Math.round(v * 10) / 10);
    }

    override public function serialize(): Dynamic {
        var o = super.serialize();
        o.min = minVal; o.max = maxVal; o.unit = unit;
        return o;
    }
}
