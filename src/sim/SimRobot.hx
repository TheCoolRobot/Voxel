package sim;

import core.TopicStore;
import util.EventBus;

/**
 * Simulated FRC robot.
 *
 * Drives a pre-baked figure-8 path around the 2025 Reefscape field using
 * Catmull-Rom interpolation. Publishes NT4 telemetry directly into
 * TopicStore (no network required).
 *
 * Topics published:
 *   /AdvantageKit/RealOutputs/Odometry/RobotPose  double[3] [x,y,rot_deg]
 *   /DriverStation/MatchTime                       double    seconds
 *   /Drive/SpeedMetersPerSec                       double
 *   /AdvantageKit/RealOutputs/Drive/GyroYawDeg    double
 *   /Shooter/FlywheelRPM                           double
 *   /Shooter/TargetRPM                             double
 *   /AutoAlign/HDeviation                          double    pixels
 *   /AutoAlign/VDeviation                          double    pixels
 *   /PathPlanner/activePath                        double[]  [x,y,rot × N]
 */
class SimRobot {
    static inline var UPDATE_HZ    = 25;       // update rate
    static inline var ROBOT_SPEED  = 3.0;      // m/s nominal
    static inline var PATH_SAMPLES = 200;      // samples in published path

    var store: TopicStore;
    var timer: haxe.Timer;

    // Parametric position: integer part = segment index, fractional = t within segment
    var param:      Float = 0.0;
    var simTime:    Float = 0.0;
    var matchTime:  Float = 135.0;
    var flywheelRpm: Float = 0.0;

    // ── Field figure-8 waypoints ─────────────────────────────────────────────
    // Field: 16.54 m wide × 8.21 m tall (blue alliance left, origin bottom-left)
    // Path crosses through the reef in two lobes
    static var WP: Array<{x:Float, y:Float}> = [
        // Blue-side lobe
        { x:  1.8, y: 4.10 },   // 0  blue wall center
        { x:  2.5, y: 2.00 },   // 1  bottom-left corner
        { x:  5.5, y: 1.40 },   // 2  bottom-left sweep
        { x:  8.27, y: 2.30 },  // 3  field center, coming under reef
        { x: 11.0, y: 1.40 },   // 4  bottom-right sweep
        { x: 14.0, y: 2.00 },   // 5  bottom-right corner
        { x: 14.8, y: 4.10 },   // 6  red wall center
        { x: 14.0, y: 6.20 },   // 7  top-right corner
        { x: 11.0, y: 6.80 },   // 8  top-right sweep
        { x:  8.27, y: 5.90 },  // 9  field center, coming over reef
        { x:  5.5, y: 6.80 },   // 10 top-left sweep
        { x:  2.5, y: 6.20 },   // 11 top-left corner
        { x:  1.8, y: 4.10 },   // 12 back to start (close loop)
    ];

    public function new(store: TopicStore, bus: EventBus) {
        this.store = store;
    }

    public function start(): Void {
        param    = 0.0;
        simTime  = 0.0;
        matchTime = 135.0;
        publishActivePath();
        timer = new haxe.Timer(Std.int(1000 / UPDATE_HZ));
        timer.run = update;
    }

    public function stop(): Void {
        if (timer != null) { timer.stop(); timer = null; }
    }

    // ── Pre-compute and publish the path as PathPlanner activePath ───────────
    function publishActivePath(): Void {
        var segCount = WP.length - 1;
        var pts: Array<Float> = [];
        for (si in 0...PATH_SAMPLES) {
            var tt  = (si / (PATH_SAMPLES - 1)) * segCount;
            var seg = Std.int(tt);
            var t   = tt - seg;
            if (seg >= segCount) { seg = segCount - 1; t = 1.0; }

            var x  = sampleCR_x(seg, t);
            var y  = sampleCR_y(seg, t);
            var dx = sampleCR_dx(seg, t);
            var dy = sampleCR_dy(seg, t);
            var heading = Math.atan2(dy, dx) * 180 / Math.PI;
            pts.push(x);
            pts.push(y);
            pts.push(heading);
        }
        store.updateValueByName("/PathPlanner/activePath", 0, pts);
    }

    // ── Update loop ──────────────────────────────────────────────────────────
    function update(): Void {
        var dt = 1.0 / UPDATE_HZ;
        simTime   += dt;
        matchTime -= dt;
        if (matchTime < 0) {
            matchTime = 135.0;
            // Re-publish path when cycle resets (not needed, but makes it feel live)
        }

        var segCount = WP.length - 1;
        var seg = Std.int(param);
        var t   = param - seg;
        if (seg >= segCount) { param = 0.0; seg = 0; t = 0.0; }

        // Current position & tangent
        var rx  = sampleCR_x(seg, t);
        var ry  = sampleCR_y(seg, t);
        var dx  = sampleCR_dx(seg, t);
        var dy  = sampleCR_dy(seg, t);
        var len = Math.sqrt(dx*dx + dy*dy);
        var heading = Math.atan2(dy, dx) * 180 / Math.PI;

        // Speed varies with curvature — slow down in tight sections
        var ddx = sampleCR_d2x(seg, t);
        var ddy = sampleCR_d2y(seg, t);
        var curvature = Math.abs(dx * ddy - dy * ddx) / Math.max(0.001, len * len * len);
        var speed = ROBOT_SPEED * (1.0 - Math.min(0.45, curvature * 1.2));

        // Advance parametric position by arc-length approximation
        var segLen = segmentLength(seg);
        param += (speed * dt) / Math.max(0.1, segLen);

        // Flywheel: spin up near red side, coast on blue side
        var targetRpm = (rx > 8.0) ? 3000.0 : 1200.0;
        flywheelRpm += (targetRpm - flywheelRpm) * 0.06;

        // Vision deviation — oscillate as if tracking a target
        var hDev = Math.sin(simTime * 2.3) * 7.0 * (1.0 - Math.min(1.0, simTime * 0.1));
        var vDev = Math.cos(simTime * 1.7) * 4.0 * (1.0 - Math.min(1.0, simTime * 0.1));

        var ts = Std.int(simTime * 1e6);
        store.updateValueByName("/AdvantageKit/RealOutputs/Odometry/RobotPose",    ts, [rx, ry, heading]);
        store.updateValueByName("/DriverStation/MatchTime",                         ts, matchTime);
        store.updateValueByName("/Drive/SpeedMetersPerSec",                         ts, speed);
        store.updateValueByName("/AdvantageKit/RealOutputs/Drive/GyroYawDeg",      ts, heading);
        store.updateValueByName("/Shooter/FlywheelRPM",                             ts, flywheelRpm);
        store.updateValueByName("/Shooter/TargetRPM",                               ts, targetRpm);
        store.updateValueByName("/AutoAlign/HDeviation",                            ts, hDev);
        store.updateValueByName("/AutoAlign/VDeviation",                            ts, vDev);
    }

    // ── Catmull-Rom helpers ──────────────────────────────────────────────────

    inline function wpx(i: Int): Float return WP[clamp(i, 0, WP.length-1)].x;
    inline function wpy(i: Int): Float return WP[clamp(i, 0, WP.length-1)].y;
    inline function clamp(v:Int, lo:Int, hi:Int): Int return v < lo ? lo : (v > hi ? hi : v);

    function sampleCR_x(seg: Int, t: Float): Float
        return cr(wpx(seg-1), wpx(seg), wpx(seg+1), wpx(seg+2), t);
    function sampleCR_y(seg: Int, t: Float): Float
        return cr(wpy(seg-1), wpy(seg), wpy(seg+1), wpy(seg+2), t);
    function sampleCR_dx(seg: Int, t: Float): Float
        return crD(wpx(seg-1), wpx(seg), wpx(seg+1), wpx(seg+2), t);
    function sampleCR_dy(seg: Int, t: Float): Float
        return crD(wpy(seg-1), wpy(seg), wpy(seg+1), wpy(seg+2), t);
    function sampleCR_d2x(seg: Int, t: Float): Float
        return crD2(wpx(seg-1), wpx(seg), wpx(seg+1), wpx(seg+2), t);
    function sampleCR_d2y(seg: Int, t: Float): Float
        return crD2(wpy(seg-1), wpy(seg), wpy(seg+1), wpy(seg+2), t);

    /** Catmull-Rom position */
    static inline function cr(p0:Float, p1:Float, p2:Float, p3:Float, t:Float): Float {
        var t2 = t*t; var t3 = t2*t;
        return 0.5 * ((2*p1) + (-p0+p2)*t + (2*p0-5*p1+4*p2-p3)*t2 + (-p0+3*p1-3*p2+p3)*t3);
    }
    /** First derivative */
    static inline function crD(p0:Float, p1:Float, p2:Float, p3:Float, t:Float): Float {
        var t2 = t*t;
        return 0.5 * ((-p0+p2) + 2*(2*p0-5*p1+4*p2-p3)*t + 3*(-p0+3*p1-3*p2+p3)*t2);
    }
    /** Second derivative */
    static inline function crD2(p0:Float, p1:Float, p2:Float, p3:Float, t:Float): Float {
        return 0.5 * (2*(2*p0-5*p1+4*p2-p3) + 6*(-p0+3*p1-3*p2+p3)*t);
    }

    /** Approximate segment length by sampling 8 sub-intervals */
    function segmentLength(seg: Int): Float {
        var len = 0.0;
        var px = sampleCR_x(seg, 0); var py = sampleCR_y(seg, 0);
        var N = 8;
        for (i in 1...(N+1)) {
            var t  = i / N;
            var nx = sampleCR_x(seg, t);
            var ny = sampleCR_y(seg, t);
            len += Math.sqrt((nx-px)*(nx-px) + (ny-py)*(ny-py));
            px = nx; py = ny;
        }
        return len;
    }
}
