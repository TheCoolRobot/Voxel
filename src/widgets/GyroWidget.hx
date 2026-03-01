package widgets;

import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.Element;
import core.TopicStore;
import util.EventBus;
import util.MathUtil;

class GyroWidget extends Widget {
    var canvas: CanvasElement;
    var ctx: CanvasRenderingContext2D;
    var angleDeg: Float = 0.0;

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "GyroWidget");
        title = "Gyro";
    }

    override function buildDOM(container: Element): Void {
        container.className += " gyro-widget";
        canvas = makeCanvas();
        container.appendChild(canvas);
        render();
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        angleDeg = value;
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
        var cy = h / 2;
        var r  = Math.min(w, h) * 0.42;

        // Outer circle
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.strokeStyle = "rgba(255,255,255,0.15)";
        ctx.lineWidth = 2;
        ctx.stroke();
        ctx.fillStyle = "rgba(15,15,26,0.8)";
        ctx.fill();

        // Tick marks
        ctx.strokeStyle = "rgba(255,255,255,0.3)";
        for (i in 0...36) {
            var a = i * Math.PI / 18;
            var len = (i % 9 == 0) ? r * 0.15 : r * 0.07;
            ctx.lineWidth = (i % 9 == 0) ? 2 : 1;
            ctx.beginPath();
            ctx.moveTo(cx + (r - len) * Math.cos(a), cy + (r - len) * Math.sin(a));
            ctx.lineTo(cx + r * Math.cos(a), cy + r * Math.sin(a));
            ctx.stroke();
        }

        // Cardinal labels (N, E, S, W rotate with gyro)
        var angleRad = MathUtil.degToRad(-angleDeg);
        var cardinals = [
            { label: "N", a: 0 },
            { label: "E", a: 90 },
            { label: "S", a: 180 },
            { label: "W", a: 270 }
        ];
        ctx.font = "bold " + Std.int(r * 0.2) + "px sans-serif";
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        for (c in cardinals) {
            var a = angleRad + MathUtil.degToRad(c.a);
            var lx = cx + (r - r*0.28) * Math.sin(a);
            var ly = cy - (r - r*0.28) * Math.cos(a);
            ctx.fillStyle = c.label == "N" ? "#ff5252" : "rgba(224,224,240,0.9)";
            ctx.fillText(c.label, lx, ly);
        }

        // Heading needle (always points up = North)
        var needleAngle = MathUtil.degToRad(-angleDeg);
        ctx.save();
        ctx.translate(cx, cy);
        ctx.rotate(needleAngle);

        // Red (north) half
        ctx.beginPath();
        ctx.moveTo(0, -r * 0.55);
        ctx.lineTo(r * 0.07, 0);
        ctx.lineTo(-r * 0.07, 0);
        ctx.closePath();
        ctx.fillStyle = "#ff5252";
        ctx.fill();

        // White (south) half
        ctx.beginPath();
        ctx.moveTo(0, r * 0.45);
        ctx.lineTo(r * 0.07, 0);
        ctx.lineTo(-r * 0.07, 0);
        ctx.closePath();
        ctx.fillStyle = "rgba(255,255,255,0.7)";
        ctx.fill();
        ctx.restore();

        // Center dot
        ctx.beginPath();
        ctx.arc(cx, cy, r * 0.06, 0, Math.PI * 2);
        ctx.fillStyle = "#e0e0f0";
        ctx.fill();

        // Angle readout
        ctx.textAlign = "center";
        ctx.textBaseline = "alphabetic";
        ctx.fillStyle = "rgba(144,144,176,0.9)";
        ctx.font = "13px monospace";
        ctx.fillText(Std.string(Math.round(MathUtil.wrapAngle(angleDeg))) + "°", cx, cy + r + 14);
    }
}
