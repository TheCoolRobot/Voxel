package util;

/**
 * Color utilities: HSV↔RGB, threshold coloring, hex strings.
 */
class ColorUtil {

    /** HSV (h 0–360, s 0–1, v 0–1) → {r,g,b} 0–255 */
    public static function hsvToRgb(h: Float, s: Float, v: Float): {r: Int, g: Int, b: Int} {
        var r = 0.0; var g = 0.0; var b = 0.0;
        if (s == 0) { r = g = b = v; }
        else {
            var sector = Math.floor(h / 60.0) % 6;
            var f = h / 60.0 - Math.floor(h / 60.0);
            var p = v * (1.0 - s);
            var q = v * (1.0 - s * f);
            var t = v * (1.0 - s * (1.0 - f));
            switch (sector) {
                case 0: r=v; g=t; b=p;
                case 1: r=q; g=v; b=p;
                case 2: r=p; g=v; b=t;
                case 3: r=p; g=q; b=v;
                case 4: r=t; g=p; b=v;
                default: r=v; g=p; b=q;
            }
        }
        return { r: Math.round(r*255), g: Math.round(g*255), b: Math.round(b*255) };
    }

    /** Returns CSS hex string like "#ff0000" */
    public static function toHex(r: Int, g: Int, b: Int): String {
        return "#" + hex2(r) + hex2(g) + hex2(b);
    }

    static function hex2(v: Int): String {
        var s = StringTools.hex(v & 0xff);
        return s.length == 1 ? "0" + s : s;
    }

    /** RGB 0–255 → CSS rgba string */
    public static function toRgba(r: Int, g: Int, b: Int, a: Float = 1.0): String {
        return 'rgba($r,$g,$b,$a)';
    }

    /**
     * Given a value [0,1] and a list of color stops [{t, r, g, b}],
     * return interpolated CSS rgba.
     */
    public static function gradient(t: Float, stops: Array<{t: Float, r: Int, g: Int, b: Int}>): String {
        if (stops.length == 0) return "#ffffff";
        if (t <= stops[0].t) { var s=stops[0]; return toRgba(s.r,s.g,s.b); }
        if (t >= stops[stops.length-1].t) { var s=stops[stops.length-1]; return toRgba(s.r,s.g,s.b); }
        for (i in 0...stops.length-1) {
            var a = stops[i]; var b = stops[i+1];
            if (t >= a.t && t <= b.t) {
                var f = (t - a.t) / (b.t - a.t);
                return toRgba(
                    Math.round(a.r + f*(b.r-a.r)),
                    Math.round(a.g + f*(b.g-a.g)),
                    Math.round(a.b + f*(b.b-a.b))
                );
            }
        }
        var s = stops[stops.length-1]; return toRgba(s.r,s.g,s.b);
    }

    /** Returns green→yellow→red color for a value ratio 0–1 */
    public static function trafficLight(t: Float): String {
        return gradient(t, [
            { t: 0.0, r: 0,   g: 200, b: 80  },
            { t: 0.5, r: 255, g: 200, b: 0   },
            { t: 1.0, r: 220, g: 40,  b: 40  }
        ]);
    }
}
