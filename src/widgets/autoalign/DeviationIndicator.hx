package widgets.autoalign;

import js.html.Element;
import util.MathUtil;

/**
 * Deviation indicator: shows a centered bar with a thumb positioned ±range.
 * Supports horizontal and vertical orientations.
 */
class DeviationIndicator {
    public var element: Element;
    var thumbEl: Element;
    var valueEl: Element;
    var barEl: Element;
    var isVertical: Bool;
    var range: Float;
    var label: String;
    var unit: String;
    var current: Float = 0.0;

    public function new(label: String, isVertical: Bool, range: Float = 50.0, unit: String = "") {
        this.label = label;
        this.isVertical = isVertical;
        this.range = range;
        this.unit = unit;
        buildDOM();
    }

    function buildDOM(): Void {
        element = js.Browser.document.createElement("div");
        element.className = "deviation-panel";

        var lbl = js.Browser.document.createElement("div");
        lbl.className = "dev-label";
        lbl.textContent = label;
        element.appendChild(lbl);

        barEl = js.Browser.document.createElement("div");
        barEl.className = isVertical ? "deviation-bar-v" : "deviation-bar-h";
        thumbEl = js.Browser.document.createElement("div");
        thumbEl.className = "deviation-thumb";
        barEl.appendChild(thumbEl);
        element.appendChild(barEl);

        // Center line
        var center = js.Browser.document.createElement("div");
        center.style.cssText = isVertical
            ? "position:absolute;left:0;right:0;top:50%;height:1px;background:rgba(255,255,255,0.15);"
            : "position:absolute;top:0;bottom:0;left:50%;width:1px;background:rgba(255,255,255,0.15);";
        barEl.appendChild(center);

        valueEl = js.Browser.document.createElement("div");
        valueEl.className = "deviation-val";
        valueEl.textContent = "0.0" + (unit.length > 0 ? " " + unit : "");
        element.appendChild(valueEl);
    }

    public function setValue(v: Float): Void {
        current = v;
        var t = MathUtil.clamp(v / range, -1.0, 1.0); // -1..1

        // Position thumb: center is 50%, move ±50%
        if (isVertical) {
            // Positive = down (more positive)
            var topPct = (0.5 + t * 0.5) * 100.0;
            thumbEl.style.top = topPct + "%";
            thumbEl.style.left = "50%";
        } else {
            var leftPct = (0.5 + t * 0.5) * 100.0;
            thumbEl.style.left = leftPct + "%";
            thumbEl.style.top = "50%";
        }

        // Color based on magnitude
        var abst = Math.abs(t);
        thumbEl.className = "deviation-thumb";
        if (abst > 0.7) thumbEl.classList.add("danger");
        else if (abst > 0.4) thumbEl.classList.add("warning");

        // Value label
        var rounded = Math.round(v * 10) / 10;
        valueEl.textContent = (v >= 0 ? "+" : "") + rounded + (unit.length > 0 ? " " + unit : "");
        if (abst > 0.7) valueEl.style.color = "var(--accent-red)";
        else if (abst > 0.4) valueEl.style.color = "var(--accent-yellow)";
        else valueEl.style.color = "var(--text-primary)";
    }
}
