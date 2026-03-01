package widgets.autoalign;

import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.Element;
import util.MathUtil;
import util.ColorUtil;

/**
 * RPM arc gauge with target and actual needles.
 */
class FerryGauge {
    public var element: Element;
    var canvas: CanvasElement;
    var ctx: CanvasRenderingContext2D;

    public var actualRpm: Float = 0.0;
    public var targetRpm: Float = 0.0;
    public var maxRpm: Float = 6000.0;

    public function new() {
        buildDOM();
    }

    function buildDOM(): Void {
        element = js.Browser.document.createElement("div");
        element.className = "deviation-panel ferry-gauge";
        element.style.cssText += "flex-direction:column;padding:4px;";

        var lbl = js.Browser.document.createElement("div");
        lbl.className = "dev-label";
        lbl.textContent = "Flywheel RPM";
        element.appendChild(lbl);

        canvas = cast(js.Browser.document.createElement("canvas"), CanvasElement);
        canvas.style.cssText = "width:100%;flex:1;display:block;min-height:60px;";
        element.appendChild(canvas);

        var valRow = js.Browser.document.createElement("div");
        valRow.style.cssText = "display:flex;justify-content:space-between;padding:0 4px;font-size:11px;margin-top:2px;";
        element.appendChild(valRow);
    }

    public function render(): Void {
        var w = element.clientWidth;
        var h = element.clientHeight - 32; // minus label and value row
        if (h < 20) h = 20;
        if (canvas.width != w || canvas.height != h) { canvas.width = w; canvas.height = h; }
        if (w == 0 || h == 0) return;
        if (ctx == null) ctx = canvas.getContext2d();

        ctx.clearRect(0, 0, w, h);

        var cx = w / 2;
        var cy = h * 0.85;
        var r  = Math.min(w * 0.44, h * 0.88);
        var startA = Math.PI;
        var endA   = 2 * Math.PI;
        var arcW   = r * 0.15;

        // Background
        ctx.beginPath();
        ctx.arc(cx, cy, r, startA, endA);
        ctx.strokeStyle = "rgba(255,255,255,0.08)";
        ctx.lineWidth = arcW;
        ctx.stroke();

        // Colored zones: 0–60% green, 60–85% yellow, 85–100% red
        var zones = [
            { min: 0.0, max: 0.6, color: "#00e676" },
            { min: 0.6, max: 0.85, color: "#ffd740" },
            { min: 0.85, max: 1.0, color: "#ff5252" }
        ];
        for (z in zones) {
            var za = startA + z.min * (endA - startA);
            var zb = startA + z.max * (endA - startA);
            ctx.beginPath();
            ctx.arc(cx, cy, r, za, zb);
            ctx.strokeStyle = z.color + "33";
            ctx.lineWidth = arcW;
            ctx.lineCap = "butt";
            ctx.stroke();
        }

        // Target needle (white dashed)
        if (targetRpm > 0) {
            var tTarget = MathUtil.clamp(targetRpm / maxRpm, 0, 1);
            var targetAngle = startA + tTarget * (endA - startA);
            ctx.save();
            ctx.strokeStyle = "rgba(255,255,255,0.7)";
            ctx.lineWidth = 2;
            ctx.setLineDash([4, 3]);
            ctx.beginPath();
            ctx.moveTo(cx, cy);
            ctx.lineTo(cx + r * 1.05 * Math.cos(targetAngle), cy + r * 1.05 * Math.sin(targetAngle));
            ctx.stroke();
            ctx.setLineDash([]);
            ctx.restore();
        }

        // Actual value arc
        var tActual = MathUtil.clamp(actualRpm / maxRpm, 0, 1);
        if (tActual > 0) {
            var actualAngle = startA + tActual * (endA - startA);
            ctx.beginPath();
            ctx.arc(cx, cy, r, startA, actualAngle);
            var color = tActual < 0.6 ? "#00e676" : (tActual < 0.85 ? "#ffd740" : "#ff5252");
            ctx.strokeStyle = color;
            ctx.lineWidth = arcW;
            ctx.lineCap = "round";
            ctx.stroke();
        }

        // RPM readout
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillStyle = getColor();
        ctx.font = "bold " + Std.int(r * 0.28) + "px monospace";
        ctx.fillText(Std.string(Math.round(actualRpm)), cx, cy - r * 0.15);

        ctx.fillStyle = "rgba(144,144,176,0.7)";
        ctx.font = "10px monospace";
        ctx.fillText("target: " + Std.string(Math.round(targetRpm)), cx, cy - r * 0.15 + r * 0.22);
    }

    function getColor(): String {
        if (targetRpm > 0) {
            var diff = Math.abs(actualRpm - targetRpm);
            var pct = diff / targetRpm;
            if (pct < 0.05) return "#00e676";
            if (pct < 0.15) return "#ffd740";
            return "#ff5252";
        }
        return "var(--text-primary)";
    }
}
