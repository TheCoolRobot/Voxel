package widgets;

import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.Element;
import core.TopicStore;
import util.EventBus;
import util.MathUtil;

typedef DataPoint = { t: Float, v: Float }

class LineGraph extends Widget {
    var canvas: CanvasElement;
    var ctx: CanvasRenderingContext2D;
    var windowSec: Float = 10.0;
    var minVal: Float = Math.NEGATIVE_INFINITY;
    var maxVal: Float = Math.POSITIVE_INFINITY;
    var lineColor: String = "#4a9eff";
    var buffer: Array<DataPoint> = [];
    var rafId: Int = -1;
    var nowFn: Void->Float;

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "LineGraph");
        title = "Graph";
        nowFn = function() return js.Browser.window.performance.now() / 1000.0;
    }

    override function buildDOM(container: Element): Void {
        container.className += " line-graph";
        canvas = makeCanvas();
        container.appendChild(canvas);
        startRender();
    }

    override public function configure(props: Dynamic): Void {
        super.configure(props);
        if (Reflect.hasField(props, "windowSec")) windowSec = props.windowSec;
        if (Reflect.hasField(props, "minVal"))    minVal = props.minVal;
        if (Reflect.hasField(props, "maxVal"))    maxVal = props.maxVal;
        if (Reflect.hasField(props, "lineColor")) lineColor = props.lineColor;
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        var v: Float = value;
        if (!Math.isFinite(v)) return;
        buffer.push({ t: nowFn(), v: v });
        // Trim old points
        var cutoff = nowFn() - windowSec - 0.5;
        while (buffer.length > 0 && buffer[0].t < cutoff) buffer.shift();
    }

    override public function onResize(): Void {
        if (canvas != null && container != null) {
            canvas.width = Std.int(container.clientWidth);
            canvas.height = Std.int(container.clientHeight);
        }
    }

    function startRender(): Void {
        rafId = js.Browser.window.requestAnimationFrame(function(_) {
            render();
            startRender();
        });
    }

    function render(): Void {
        if (canvas == null) return;
        var w = canvas.clientWidth;
        var h = canvas.clientHeight;
        if (canvas.width != w || canvas.height != h) { canvas.width = w; canvas.height = h; }
        if (w == 0 || h == 0) return;

        if (ctx == null) ctx = canvas.getContext2d();
        ctx.clearRect(0, 0, w, h);

        var now = nowFn();
        var tMin = now - windowSec;
        var tMax = now;

        // Background
        ctx.fillStyle = "rgba(15,15,26,0.9)";
        ctx.fillRect(0, 0, w, h);

        // Grid lines
        ctx.strokeStyle = "rgba(255,255,255,0.05)";
        ctx.lineWidth = 1;
        var gridLines = 5;
        for (i in 0...gridLines+1) {
            var y = h * i / gridLines;
            ctx.beginPath();
            ctx.moveTo(0, y);
            ctx.lineTo(w, y);
            ctx.stroke();
        }

        if (buffer.length < 2) return;

        // Auto-range
        var lo = Math.POSITIVE_INFINITY;
        var hi = Math.NEGATIVE_INFINITY;
        for (p in buffer) {
            if (p.v < lo) lo = p.v;
            if (p.v > hi) hi = p.v;
        }
        if (Math.isFinite(minVal)) lo = minVal;
        if (Math.isFinite(maxVal)) hi = maxVal;
        if (hi - lo < 1e-6) { lo -= 0.5; hi += 0.5; }
        var range = hi - lo;
        var pad = range * 0.1;
        lo -= pad; hi += pad;

        // Axis labels
        ctx.fillStyle = "rgba(144,144,176,0.8)";
        ctx.font = "10px monospace";
        ctx.textAlign = "right";
        for (i in 0...gridLines+1) {
            var frac = 1.0 - i / gridLines;
            var val = lo + frac * (hi - lo);
            ctx.fillText(formatVal(val), w - 3, h * i / gridLines + 10);
        }

        // Data line
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 2;
        ctx.shadowColor = lineColor;
        ctx.shadowBlur = 4;
        ctx.beginPath();
        var first = true;
        for (p in buffer) {
            var px = (p.t - tMin) / (tMax - tMin) * w;
            var py = (1.0 - (p.v - lo) / (hi - lo)) * h;
            py = MathUtil.clamp(py, 0, h);
            if (first) { ctx.moveTo(px, py); first = false; }
            else ctx.lineTo(px, py);
        }
        ctx.stroke();
        ctx.shadowBlur = 0;

        // Current value
        if (buffer.length > 0) {
            var last = buffer[buffer.length - 1];
            ctx.fillStyle = lineColor;
            ctx.font = "bold 13px monospace";
            ctx.textAlign = "left";
            ctx.fillText(formatVal(last.v), 6, 16);
        }
    }

    function formatVal(v: Float): String {
        if (Math.abs(v) >= 1000) return Std.string(Math.round(v));
        if (Math.abs(v) >= 10)   return Std.string(Math.round(v * 10) / 10);
        return Std.string(Math.round(v * 100) / 100);
    }

    override public function destroy(): Void {
        super.destroy();
        if (rafId >= 0) js.Browser.window.cancelAnimationFrame(rafId);
    }

    override public function serialize(): Dynamic {
        var o = super.serialize();
        o.windowSec = windowSec;
        return o;
    }
}
