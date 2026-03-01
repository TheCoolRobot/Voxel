package widgets.autoalign;

import util.MathUtil;
import haxe.Json;

enum abstract PathMode(String) to String {
    var Pixels = "pixels";
    var FieldSpace = "fieldspace";
    var WPILibTrajectory = "trajectory";
}

typedef PathPoint = { x: Float, y: Float }

/**
 * Converts path data from NT into canvas pixel coordinates.
 *
 * Mode 1 - FieldSpace: Robot publishes float[] [x0,y0, x1,y1, ...] in field meters.
 *   Uses configurable 3×3 homography H to project field→camera pixels.
 * Mode 2 - Pixels: Robot publishes pixel coords directly (float[] [px0,py0, ...]).
 * Mode 3 - WPILibTrajectory: NT publishes WPILib Trajectory JSON string.
 *   Samples at 0.1s intervals, applies homography.
 */
class PathProjector {
    public var mode: PathMode = Pixels;

    /** Homography matrix (3×3, row-major). Used in FieldSpace and Trajectory modes. */
    public var H: Array<Float> = [1,0,0, 0,1,0, 0,0,1]; // identity

    /** Camera display dimensions (needed to clip) */
    public var displayW: Float = 640;
    public var displayH: Float = 480;

    public function new() {}

    /**
     * Convert raw NT value → array of canvas {x,y} points.
     * canvasW/canvasH: actual canvas pixel size.
     * imgNatW/imgNatH: natural size the camera image was captured at (for pixel scaling).
     */
    public function project(value: Dynamic, canvasW: Float, canvasH: Float,
                            imgNatW: Float = 640, imgNatH: Float = 480): Array<PathPoint> {
        return switch (mode) {
            case Pixels:         projectPixels(value, canvasW, canvasH, imgNatW, imgNatH);
            case FieldSpace:     projectFieldSpace(value, canvasW, canvasH);
            case WPILibTrajectory: projectTrajectory(value, canvasW, canvasH);
        };
    }

    function projectPixels(value: Dynamic, cw: Float, ch: Float, nw: Float, nh: Float): Array<PathPoint> {
        var arr = toFloatArray(value);
        var pts: Array<PathPoint> = [];
        var i = 0;
        while (i + 1 < arr.length) {
            pts.push({
                x: arr[i]   / nw * cw,
                y: arr[i+1] / nh * ch
            });
            i += 2;
        }
        return pts;
    }

    function projectFieldSpace(value: Dynamic, cw: Float, ch: Float): Array<PathPoint> {
        var arr = toFloatArray(value);
        var pts: Array<PathPoint> = [];
        var i = 0;
        while (i + 1 < arr.length) {
            var p = MathUtil.applyHomography(H, arr[i], arr[i+1]);
            // Scale to canvas
            pts.push({
                x: p.x / displayW * cw,
                y: p.y / displayH * ch
            });
            i += 2;
        }
        return pts;
    }

    function projectTrajectory(value: Dynamic, cw: Float, ch: Float): Array<PathPoint> {
        var json: String = Std.isOfType(value, String) ? value : haxe.Json.stringify(value);
        try {
            var traj: Dynamic = Json.parse(json);
            var states: Array<Dynamic> = traj.states != null ? traj.states : traj;
            if (states == null) return [];

            var pts: Array<PathPoint> = [];
            var prevT: Float = -1e9;
            for (state in states) {
                var t: Float = state.time != null ? state.time : state.t;
                if (prevT >= 0 && t - prevT < 0.1) continue;
                prevT = t;
                var pose: Dynamic = state.pose != null ? state.pose : state;
                var fx: Float = pose.translation != null ? pose.translation.x : pose.x;
                var fy: Float = pose.translation != null ? pose.translation.y : pose.y;
                var p = MathUtil.applyHomography(H, fx, fy);
                pts.push({
                    x: p.x / displayW * cw,
                    y: p.y / displayH * ch
                });
            }
            return pts;
        } catch (e: Dynamic) {
            trace("PathProjector: trajectory parse error: " + e);
            return [];
        }
    }

    static function toFloatArray(value: Dynamic): Array<Float> {
        if (Std.isOfType(value, Array)) return cast value;
        if (Std.isOfType(value, String)) {
            try { return haxe.Json.parse(value); } catch (_) {}
        }
        return [];
    }

    public function serialize(): Dynamic {
        return { mode: (mode : String), H: H, displayW: displayW, displayH: displayH };
    }

    public function configure(props: Dynamic): Void {
        if (Reflect.hasField(props, "pathMode")) mode = props.pathMode;
        if (Reflect.hasField(props, "H"))        H = props.H;
        if (Reflect.hasField(props, "displayW")) displayW = props.displayW;
        if (Reflect.hasField(props, "displayH")) displayH = props.displayH;
    }
}
