package widgets.autoalign;

import js.html.CanvasElement;
import js.html.CanvasRenderingContext2D;
import js.html.Element;
import js.html.ImageElement;

/**
 * MJPEG camera feed with a canvas overlay for path drawing.
 */
class CameraOverlay {
    public var element: Element;
    var img: ImageElement;
    var canvas: CanvasElement;
    var ctx: CanvasRenderingContext2D;
    var pathPoints: Array<{x:Float,y:Float}> = [];
    var expectedPoints: Array<{x:Float,y:Float}> = [];
    var projector: PathProjector;

    public function new(projector: PathProjector) {
        this.projector = projector;
        buildDOM();
    }

    function buildDOM(): Void {
        element = js.Browser.document.createElement("div");
        element.className = "autoalign-camera-row";

        img = cast(js.Browser.document.createElement("img"), ImageElement);
        img.alt = "Limelight feed";
        img.style.cssText = "width:100%;height:100%;object-fit:contain;";
        element.appendChild(img);

        canvas = cast(js.Browser.document.createElement("canvas"), CanvasElement);
        canvas.style.cssText = "position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;";
        element.appendChild(canvas);
    }

    public function setUrl(url: String): Void {
        img.src = url.length > 0 ? url : "";
    }

    public function setPathPoints(pts: Array<{x:Float,y:Float}>): Void {
        pathPoints = pts;
        drawOverlay();
    }

    public function setExpectedPoints(pts: Array<{x:Float,y:Float}>): Void {
        expectedPoints = pts;
        drawOverlay();
    }

    public function redraw(): Void {
        drawOverlay();
    }

    function drawOverlay(): Void {
        var w = element.clientWidth;
        var h = element.clientHeight;
        if (canvas.width != w || canvas.height != h) { canvas.width = w; canvas.height = h; }
        if (w == 0 || h == 0) return;
        if (ctx == null) ctx = canvas.getContext2d();

        ctx.clearRect(0, 0, w, h);

        // Draw expected path (dashed, dim)
        if (expectedPoints.length >= 2) {
            drawPath(expectedPoints, "rgba(255,255,100,0.4)", 2, true);
        }

        // Draw current/planned path
        if (pathPoints.length >= 2) {
            drawPath(pathPoints, "#4a9eff", 2.5, false);
        }

        // Draw path endpoints
        for (i in 0...pathPoints.length) {
            var p = pathPoints[i];
            ctx.beginPath();
            ctx.arc(p.x, p.y, i == 0 || i == pathPoints.length-1 ? 5 : 3, 0, Math.PI*2);
            ctx.fillStyle = i == pathPoints.length-1 ? "#00e676" : "rgba(74,158,255,0.8)";
            ctx.fill();
        }
    }

    function drawPath(pts: Array<{x:Float,y:Float}>, color: String, lineW: Float, dashed: Bool): Void {
        if (pts.length < 2) return;
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (i in 1...pts.length) ctx.lineTo(pts[i].x, pts[i].y);
        ctx.strokeStyle = color;
        ctx.lineWidth = lineW;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";
        if (dashed) ctx.setLineDash([6, 4]);
        else ctx.setLineDash([]);
        ctx.stroke();
        ctx.setLineDash([]);
    }
}
