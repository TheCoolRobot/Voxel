package widgets;

import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.ImageElement;
import js.html.Element;
import core.TopicStore;
import util.EventBus;
import util.MathUtil;

class FieldWidget extends Widget {
    var canvas: CanvasElement;
    var ctx: CanvasRenderingContext2D;
    var fieldImg: ImageElement;
    var imgLoaded: Bool = false;

    // Field config
    var fieldW: Float = 16.54;
    var fieldH: Float = 8.21;
    var alliance: String = "blue";

    // Robot pose [x, y, rotation_deg] from odometry
    var robotX: Float    = 0.0;
    var robotY: Float    = 0.0;
    var robotAngle: Float = 0.0;
    var poseReceived: Bool = false;   // true once real odometry arrives

    // PathPlanner topics (configurable)
    var pathTopic: String   = "/PathPlanner/activePath";
    var showPath: Bool      = true;
    var pathUnsub: Null<Void->Void> = null;   // returned by store.subscribe()

    // Parsed path points: flat double[] → [{x,y,a}]
    // PathPlannerLib publishes each state as [x_m, y_m, rot_deg] interleaved
    var pathPoints: Array<{x:Float, y:Float, a:Float}> = [];

    // Ghost poses (e.g. vision targets)
    var ghostPoses: Array<{x:Float,y:Float,a:Float,color:String}> = [];

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "FieldWidget");
        title = "Field";
        loadFieldImage();
    }

    function loadFieldImage(): Void {
        fieldImg = cast(js.Browser.document.createElement("img"), ImageElement);
        fieldImg.onload = function(_) { imgLoaded = true; render(); };
        fieldImg.src = "assets/field/2025-reefscape.png";
    }

    override function buildDOM(container: Element): Void {
        container.className += " field-widget";
        canvas = makeCanvas();
        container.appendChild(canvas);
    }

    override public function configure(props: Dynamic): Void {
        super.configure(props);
        if (Reflect.hasField(props, "alliance"))  alliance  = props.alliance;
        if (Reflect.hasField(props, "showPath")) {
            var raw = props.showPath;
            showPath = (Std.string(raw) == "true" || raw == true);
        }
        if (Reflect.hasField(props, "pathTopic")) {
            var newPath: String = Std.string(props.pathTopic);
            if (newPath != pathTopic) {
                // Unsubscribe old path topic
                if (pathUnsub != null) { pathUnsub(); pathUnsub = null; }
                pathTopic  = newPath;
                pathPoints = [];
            }
        }
        // Subscribe to PathPlanner active-path topic
        if (showPath && pathTopic != "") {
            if (pathUnsub == null)
                pathUnsub = store.subscribe(pathTopic, onPathUpdate);
        } else if (!showPath && pathUnsub != null) {
            pathUnsub(); pathUnsub = null;
        }
        render();
    }

    // Called for the primary pose topic (set via Widget.configure ntTopic)
    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        if (topic == pathTopic) {
            onPathUpdate(topic, value);
            return;
        }
        // Odometry pose: double[] [x, y, rotation_deg]
        if (Std.isOfType(value, Array)) {
            var arr: Array<Dynamic> = value;
            if (arr.length >= 2) {
                robotX = arr[0]; robotY = arr[1];
                poseReceived = true;
            }
            if (arr.length >= 3) robotAngle = arr[2];
        }
        render();
    }

    // Handle PathPlanner activePath updates (String->Dynamic->Void for store.subscribe)
    function onPathUpdate(_topic: String, value: Dynamic): Void {
        pathPoints = [];
        if (!Std.isOfType(value, Array)) { render(); return; }
        var arr: Array<Dynamic> = value;
        // PathPlannerLib encodes path states as flat triples: [x0, y0, rot0, x1, y1, rot1, …]
        var i = 0;
        while (i + 2 < arr.length) {
            pathPoints.push({
                x: arr[i],
                y: arr[i + 1],
                a: arr[i + 2]
            });
            i += 3;
        }
        // Seed robot starting position from path[0] if odometry hasn't arrived yet
        if (!poseReceived && pathPoints.length > 0) {
            robotX     = pathPoints[0].x;
            robotY     = pathPoints[0].y;
            robotAngle = pathPoints[0].a;
        }
        render();
    }

    override public function onResize(): Void {
        if (canvas != null && container != null) {
            canvas.width  = Std.int(container.clientWidth);
            canvas.height = Std.int(container.clientHeight);
            render();
        }
    }

    // ── Coordinate conversion ────────────────────────────────────────────────
    function fieldToCanvas(fx: Float, fy: Float, cw: Float, ch: Float): {x:Float,y:Float} {
        var px: Float; var py: Float;
        if (alliance == "red") {
            px = (1.0 - fx / fieldW) * cw;
            py = (fy / fieldH) * ch;
        } else {
            px = (fx / fieldW) * cw;
            py = (1.0 - fy / fieldH) * ch;
        }
        return { x: px, y: py };
    }

    // ── Render ───────────────────────────────────────────────────────────────
    function render(): Void {
        if (canvas == null) return;
        var w = canvas.clientWidth;
        var h = canvas.clientHeight;
        if (canvas.width != w || canvas.height != h) { canvas.width = w; canvas.height = h; }
        if (w == 0 || h == 0) return;
        if (ctx == null) ctx = canvas.getContext2d();

        ctx.clearRect(0, 0, w, h);

        if (imgLoaded) {
            ctx.drawImage(fieldImg, 0, 0, w, h);
            ctx.fillStyle = "rgba(0,0,0,0.25)";
            ctx.fillRect(0, 0, w, h);
        } else {
            ctx.fillStyle = "#0d2040";
            ctx.fillRect(0, 0, w, h);
            ctx.strokeStyle = "#1a4070";
            ctx.lineWidth = 2;
            ctx.strokeRect(2, 2, w-4, h-4);
            ctx.fillStyle = "#3060a0";
            ctx.textAlign = "center";
            ctx.font = "12px sans-serif";
            ctx.fillText("Field image loading...", w/2, h/2);
        }

        // Draw planned path (behind the robot)
        if (showPath && pathPoints.length > 1) drawPath(w, h);

        // Starting pose marker (first path point)
        if (showPath && pathPoints.length > 0 && !poseReceived) {
            var pt = pathPoints[0];
            drawStartMarker(pt.x, pt.y, w, h);
        }

        // Robot pose
        drawRobot(robotX, robotY, robotAngle, "#4a9eff", w, h);

        // Ghost poses
        for (g in ghostPoses) drawRobot(g.x, g.y, g.a, g.color, w, h);
    }

    // ── Draw planned path ────────────────────────────────────────────────────
    function drawPath(cw: Float, ch: Float): Void {
        // Path line — cyan gradient along the trajectory
        ctx.save();
        ctx.lineWidth   = 2.5;
        ctx.lineJoin    = "round";
        ctx.lineCap     = "round";
        ctx.strokeStyle = "rgba(0,240,220,0.75)";
        ctx.shadowColor = "rgba(0,240,220,0.4)";
        ctx.shadowBlur  = 6;

        ctx.beginPath();
        var p0 = fieldToCanvas(pathPoints[0].x, pathPoints[0].y, cw, ch);
        ctx.moveTo(p0.x, p0.y);
        for (i in 1...pathPoints.length) {
            var p = fieldToCanvas(pathPoints[i].x, pathPoints[i].y, cw, ch);
            ctx.lineTo(p.x, p.y);
        }
        ctx.stroke();
        ctx.restore();

        // Direction tick-marks every ~10 points to show heading along the path
        var step = Std.int(Math.max(1, Math.round(pathPoints.length / 12)));
        var tickLen = Math.min(cw, ch) * 0.025;
        ctx.save();
        ctx.strokeStyle = "rgba(0,240,220,0.55)";
        ctx.lineWidth = 1.5;
        for (i in 0...pathPoints.length) {
            if (i % step != 0) continue;
            var pt = pathPoints[i];
            var pc = fieldToCanvas(pt.x, pt.y, cw, ch);
            var angleRad = alliance == "red"
                ? MathUtil.degToRad(pt.a)
                : MathUtil.degToRad(-pt.a);
            ctx.save();
            ctx.translate(pc.x, pc.y);
            ctx.rotate(angleRad);
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(0, -tickLen);
            ctx.stroke();
            ctx.restore();
        }
        ctx.restore();

        // End-goal marker — hollow diamond
        var last = pathPoints[pathPoints.length - 1];
        var lp = fieldToCanvas(last.x, last.y, cw, ch);
        var r  = Math.min(cw, ch) * 0.022;
        ctx.save();
        ctx.strokeStyle = "#00f0dc";
        ctx.lineWidth   = 2;
        ctx.fillStyle   = "rgba(0,240,220,0.18)";
        ctx.beginPath();
        ctx.moveTo(lp.x,     lp.y - r);
        ctx.lineTo(lp.x + r, lp.y);
        ctx.lineTo(lp.x,     lp.y + r);
        ctx.lineTo(lp.x - r, lp.y);
        ctx.closePath();
        ctx.fill();
        ctx.stroke();
        ctx.restore();
    }

    // ── Starting-pose marker (used before odometry arrives) ──────────────────
    function drawStartMarker(fx: Float, fy: Float, cw: Float, ch: Float): Void {
        var p  = fieldToCanvas(fx, fy, cw, ch);
        var r  = Math.min(cw, ch) * 0.028;
        ctx.save();
        ctx.strokeStyle = "rgba(255,200,0,0.85)";
        ctx.lineWidth   = 2;
        ctx.fillStyle   = "rgba(255,200,0,0.15)";
        ctx.setLineDash([4, 3]);
        ctx.beginPath();
        ctx.arc(p.x, p.y, r, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        ctx.setLineDash([]);
        // "S" label
        ctx.fillStyle   = "rgba(255,200,0,0.9)";
        ctx.font        = 'bold ${Std.int(r * 1.2)}px sans-serif';
        ctx.textAlign   = "center";
        ctx.textBaseline = "middle";
        ctx.fillText("S", p.x, p.y);
        ctx.restore();
    }

    // ── Robot box ────────────────────────────────────────────────────────────
    function drawRobot(fx: Float, fy: Float, angleDeg: Float, color: String, cw: Float, ch: Float): Void {
        var p = fieldToCanvas(fx, fy, cw, ch);
        var scale = Math.min(cw, ch) / fieldW * 0.8;
        var rw = scale * 0.9;
        var rh = scale * 0.9;

        ctx.save();
        ctx.translate(p.x, p.y);

        var canvasAngle = alliance == "red"
            ? MathUtil.degToRad(angleDeg)
            : MathUtil.degToRad(-angleDeg);
        ctx.rotate(canvasAngle);

        ctx.fillStyle   = color + "88";
        ctx.strokeStyle = color;
        ctx.lineWidth   = 2;
        ctx.fillRect(-rw/2, -rh/2, rw, rh);
        ctx.strokeRect(-rw/2, -rh/2, rw, rh);

        // Direction arrow
        ctx.strokeStyle = "#fff";
        ctx.lineWidth   = 2;
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(0, -rh * 0.45);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(-rw*0.15, -rh*0.3);
        ctx.lineTo(0, -rh*0.45);
        ctx.lineTo(rw*0.15, -rh*0.3);
        ctx.stroke();

        ctx.restore();
    }

    override public function destroy(): Void {
        super.destroy();
        if (pathUnsub != null) { pathUnsub(); pathUnsub = null; }
    }

    override public function serialize(): Dynamic {
        var o = super.serialize();
        o.alliance  = alliance;
        o.showPath  = showPath;
        o.pathTopic = pathTopic;
        return o;
    }
}
