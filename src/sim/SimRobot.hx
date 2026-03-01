package sim;

import core.TopicStore;
import util.EventBus;

/**
 * Simulated FRC robot.
 *
 * Drives a Catmull-Rom figure-8 path around the 2025 Reefscape field and
 * publishes realistic NT4 telemetry directly into TopicStore.
 *
 * Shooter simulation:
 *   - Fires a shot every 3-7 s when in range of the blue alliance speaker
 *   - Hit probability degrades with distance (95 % at 2 m → 30 % at 8 m)
 *   - Publishes /Shooter/Fired (rising edge) and, after ~1.4 s,
 *     /Shooter/NoteScored (true on hit, false on miss)
 *   - Publishes /Drive/DistanceToTarget for the ShooterTunerWidget
 */
class SimRobot {
    static inline var UPDATE_HZ   = 25;
    static inline var ROBOT_SPEED = 3.0;      // m/s nominal
    static inline var PATH_SAMPLES = 200;

    // Speaker position (blue alliance wall, Reefscape 2025)
    static inline var SPEAKER_X   = 0.18;
    static inline var SPEAKER_Y   = 5.55;
    static inline var SPEAKER_H   = 2.11;     // m — target height
    static inline var CAM_H       = 0.28;
    static inline var MOUNT_DEG   = 25.0;

    var store: TopicStore;
    var timer: haxe.Timer;

    // Parametric path state
    var param:     Float = 0.0;
    var simTime:   Float = 0.0;
    var matchTime: Float = 135.0;
    var flywheelRpm: Float = 0.0;

    // Shooter simulation state
    var timeSinceShot: Float = 3.0;
    var nextShotAt:    Float = 3.5;
    var shotFrames:    Int   = 0;    // frames remaining for Fired=true
    var scoreDelay:    Float = -1.0; // seconds until NoteScored publishes
    var scoreFrames:   Int   = 0;    // frames remaining for NoteScored=true
    var scoreIsHit:    Bool  = false;

    // ── Figure-8 waypoints (field metres, 16.54 × 8.21) ─────────────────────
    static var WP: Array<{x:Float, y:Float}> = [
        { x:  1.8, y: 4.10 },   // 0  blue wall center
        { x:  2.5, y: 2.00 },   // 1  bottom-left
        { x:  5.5, y: 1.40 },   // 2  bottom sweep
        { x:  8.27, y: 2.30 },  // 3  center low
        { x: 11.0, y: 1.40 },   // 4  bottom-right sweep
        { x: 14.0, y: 2.00 },   // 5  bottom-right
        { x: 14.8, y: 4.10 },   // 6  red wall center
        { x: 14.0, y: 6.20 },   // 7  top-right
        { x: 11.0, y: 6.80 },   // 8  top-right sweep
        { x:  8.27, y: 5.90 },  // 9  center high
        { x:  5.5, y: 6.80 },   // 10 top-left sweep
        { x:  2.5, y: 6.20 },   // 11 top-left
        { x:  1.8, y: 4.10 },   // 12 back to start (closes loop)
    ];

    public function new(store: TopicStore, bus: EventBus) {
        this.store = store;
    }

    public function start(): Void {
        param = 0.0; simTime = 0.0; matchTime = 135.0;
        timeSinceShot = 3.0; nextShotAt = 3.5;
        shotFrames = 0; scoreDelay = -1.0; scoreFrames = 0;
        publishActivePath();
        timer = new haxe.Timer(Std.int(1000 / UPDATE_HZ));
        timer.run = update;
    }

    public function stop(): Void {
        if (timer != null) { timer.stop(); timer = null; }
    }

    // ── Pre-compute & publish path overlay ───────────────────────────────────
    function publishActivePath(): Void {
        var segCount = WP.length - 1;
        var pts: Array<Float> = [];
        for (si in 0...PATH_SAMPLES) {
            var tt  = (si / (PATH_SAMPLES - 1)) * segCount;
            var seg = Std.int(tt); var t = tt - seg;
            if (seg >= segCount) { seg = segCount - 1; t = 1.0; }
            var x = crX(seg, t); var y = crY(seg, t);
            var heading = Math.atan2(crDy(seg, t), crDx(seg, t)) * 180 / Math.PI;
            pts.push(x); pts.push(y); pts.push(heading);
        }
        store.updateValueByName("/PathPlanner/activePath", 0, pts);
    }

    // ── Main update (25 Hz) ───────────────────────────────────────────────────
    function update(): Void {
        var dt = 1.0 / UPDATE_HZ;
        simTime   += dt;
        matchTime -= dt;
        if (matchTime < 0) matchTime = 135.0;

        // ── Robot pose ───────────────────────────────────────────────────────
        var segCount = WP.length - 1;
        var seg = Std.int(param); var t = param - seg;
        if (seg >= segCount) { param = 0.0; seg = 0; t = 0.0; }

        var rx = crX(seg, t); var ry = crY(seg, t);
        var dx = crDx(seg, t); var dy = crDy(seg, t);
        var len = Math.sqrt(dx*dx + dy*dy);
        var heading = Math.atan2(dy, dx) * 180 / Math.PI;

        // Slow down at high curvature
        var d2x = crD2x(seg, t); var d2y = crD2y(seg, t);
        var curv = Math.abs(dx*d2y - dy*d2x) / Math.max(0.001, len*len*len);
        var speed = ROBOT_SPEED * (1.0 - Math.min(0.45, curv * 1.2));
        param += (speed * dt) / Math.max(0.1, segLen(seg));

        // ── Derived sensor values ─────────────────────────────────────────────
        var ddx = rx - SPEAKER_X; var ddy = ry - SPEAKER_Y;
        var dist = Math.sqrt(ddx*ddx + ddy*ddy);

        var targetRpm = rx > 8.0 ? 3000.0 : 1200.0;
        flywheelRpm += (targetRpm - flywheelRpm) * 0.06;

        var hDev = Math.sin(simTime * 2.3) * 7.0;
        var vDev = Math.cos(simTime * 1.7) * 4.0;

        // Limelight TY from geometry
        var rad = Math.atan2(SPEAKER_H - CAM_H, Math.max(0.1, dist));
        var tyDeg = rad * 180 / Math.PI - MOUNT_DEG;

        var ts = Std.int(simTime * 1e6);

        // ── Publish core telemetry ────────────────────────────────────────────
        store.updateValueByName("/AdvantageKit/RealOutputs/Odometry/RobotPose",   ts, [rx, ry, heading]);
        store.updateValueByName("/DriverStation/MatchTime",                        ts, matchTime);
        store.updateValueByName("/Drive/SpeedMetersPerSec",                        ts, speed);
        store.updateValueByName("/AdvantageKit/RealOutputs/Drive/GyroYawDeg",     ts, heading);
        store.updateValueByName("/Shooter/FlywheelRPM",                            ts, flywheelRpm);
        store.updateValueByName("/Shooter/TargetRPM",                              ts, targetRpm);
        store.updateValueByName("/AutoAlign/HDeviation",                           ts, hDev);
        store.updateValueByName("/AutoAlign/VDeviation",                           ts, vDev);
        store.updateValueByName("/Drive/DistanceToTarget",                         ts, dist);
        store.updateValueByName("/limelight/ty",                                   ts, tyDeg);

        // ── Shooter simulation ────────────────────────────────────────────────
        timeSinceShot += dt;

        // Maintain Fired signal for shotFrames
        if (shotFrames > 0) {
            store.updateValueByName("/Shooter/Fired", ts, true);
            shotFrames--;
        } else {
            store.updateValueByName("/Shooter/Fired", ts, false);
        }

        // Count down to scoring event
        if (scoreDelay >= 0) {
            scoreDelay -= dt;
            if (scoreDelay < 0) scoreFrames = 3;
        }
        if (scoreFrames > 0) {
            store.updateValueByName("/Shooter/NoteScored", ts, scoreIsHit);
            scoreFrames--;
        } else {
            store.updateValueByName("/Shooter/NoteScored", ts, false);
        }

        // Fire a new shot when interval elapsed and robot is in shooting range
        var inRange = dist >= 1.5 && dist <= 9.0;
        if (timeSinceShot >= nextShotAt && inRange) {
            timeSinceShot = 0.0;
            nextShotAt    = 3.0 + Math.random() * 4.0;
            shotFrames    = 3;
            // Hit probability: 95% at 2m, degrades ~8%/m
            var hitProb   = Math.max(0.25, 0.95 - (dist - 2.0) * 0.085);
            scoreIsHit    = Math.random() < hitProb;
            scoreDelay    = 1.2 + Math.random() * 0.5;
        }
    }

    // ── Catmull-Rom helpers ───────────────────────────────────────────────────
    inline function wpx(i: Int): Float return WP[clampI(i)].x;
    inline function wpy(i: Int): Float return WP[clampI(i)].y;
    inline function clampI(i: Int): Int return i < 0 ? 0 : (i >= WP.length ? WP.length-1 : i);

    function crX(seg: Int, t: Float):  Float return cr(wpx(seg-1), wpx(seg), wpx(seg+1), wpx(seg+2), t);
    function crY(seg: Int, t: Float):  Float return cr(wpy(seg-1), wpy(seg), wpy(seg+1), wpy(seg+2), t);
    function crDx(seg: Int, t: Float): Float return crd(wpx(seg-1), wpx(seg), wpx(seg+1), wpx(seg+2), t);
    function crDy(seg: Int, t: Float): Float return crd(wpy(seg-1), wpy(seg), wpy(seg+1), wpy(seg+2), t);
    function crD2x(seg: Int, t: Float): Float return crd2(wpx(seg-1), wpx(seg), wpx(seg+1), wpx(seg+2), t);
    function crD2y(seg: Int, t: Float): Float return crd2(wpy(seg-1), wpy(seg), wpy(seg+1), wpy(seg+2), t);

    static inline function cr(p0:Float,p1:Float,p2:Float,p3:Float,t:Float): Float {
        var t2=t*t; var t3=t2*t;
        return 0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t2+(-p0+3*p1-3*p2+p3)*t3);
    }
    static inline function crd(p0:Float,p1:Float,p2:Float,p3:Float,t:Float): Float {
        var t2=t*t;
        return 0.5*((-p0+p2)+2*(2*p0-5*p1+4*p2-p3)*t+3*(-p0+3*p1-3*p2+p3)*t2);
    }
    static inline function crd2(p0:Float,p1:Float,p2:Float,p3:Float,t:Float): Float {
        return 0.5*(2*(2*p0-5*p1+4*p2-p3)+6*(-p0+3*p1-3*p2+p3)*t);
    }

    function segLen(seg: Int): Float {
        var len = 0.0; var px = crX(seg, 0); var py = crY(seg, 0);
        for (i in 1...9) {
            var nx = crX(seg, i/8.0); var ny = crY(seg, i/8.0);
            len += Math.sqrt((nx-px)*(nx-px)+(ny-py)*(ny-py));
            px=nx; py=ny;
        }
        return len;
    }
}
