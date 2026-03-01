package util;

/**
 * Math utilities: clamp, lerp, homography projection.
 */
class MathUtil {

    public static inline function clamp(v: Float, lo: Float, hi: Float): Float {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    public static inline function lerp(a: Float, b: Float, t: Float): Float {
        return a + (b - a) * t;
    }

    public static inline function inverseLerp(a: Float, b: Float, v: Float): Float {
        return (b != a) ? (v - a) / (b - a) : 0.0;
    }

    public static inline function remapRange(v: Float, inLo: Float, inHi: Float, outLo: Float, outHi: Float): Float {
        return lerp(outLo, outHi, inverseLerp(inLo, inHi, v));
    }

    public static inline function degToRad(deg: Float): Float return deg * Math.PI / 180.0;
    public static inline function radToDeg(rad: Float): Float return rad * 180.0 / Math.PI;

    public static inline function wrapAngle(deg: Float): Float {
        var a = deg % 360.0;
        return a < 0 ? a + 360.0 : a;
    }

    /**
     * Apply a 3×3 homography matrix H (row-major, 9 values) to a 2D point.
     * Returns {x, y} in destination coordinate system.
     */
    public static function applyHomography(H: Array<Float>, px: Float, py: Float): {x: Float, y: Float} {
        var w = H[6]*px + H[7]*py + H[8];
        if (Math.abs(w) < 1e-9) return {x: 0.0, y: 0.0};
        return {
            x: (H[0]*px + H[1]*py + H[2]) / w,
            y: (H[3]*px + H[4]*py + H[5]) / w
        };
    }

    /**
     * Compute 3×3 homography from 4 src→dst point pairs using DLT.
     * pts: [{sx,sy,dx,dy}, ...]  (must have exactly 4 entries)
     */
    public static function computeHomography(pts: Array<{sx:Float,sy:Float,dx:Float,dy:Float}>): Array<Float> {
        // Build 8×9 matrix A, solve via SVD / Gaussian elimination
        // For simplicity, use Gaussian elimination on 8×9 augmented system
        var A: Array<Array<Float>> = [];
        for (p in pts) {
            var sx = p.sx; var sy = p.sy; var dx = p.dx; var dy = p.dy;
            A.push([-sx, -sy, -1.0, 0.0, 0.0, 0.0, dx*sx, dx*sy, dx]);
            A.push([0.0, 0.0, 0.0, -sx, -sy, -1.0, dy*sx, dy*sy, dy]);
        }
        // Last element h[8]=1 (fix scale), reduce 8×8
        // Solve A[:8][:8] * x = -A[:8][8]
        var n = 8;
        var b: Array<Float> = [];
        for (i in 0...n) {
            b.push(-A[i][8]);
        }
        // Gaussian elimination
        for (col in 0...n) {
            // pivot
            var maxRow = col;
            var maxVal = Math.abs(A[col][col]);
            for (row in col+1...n) {
                if (Math.abs(A[row][col]) > maxVal) { maxVal = Math.abs(A[row][col]); maxRow = row; }
            }
            var tmp = A[col]; A[col] = A[maxRow]; A[maxRow] = tmp;
            var tb = b[col]; b[col] = b[maxRow]; b[maxRow] = tb;

            for (row in col+1...n) {
                var factor = A[row][col] / A[col][col];
                for (k in col...n) A[row][k] -= factor * A[col][k];
                b[row] -= factor * b[col];
            }
        }
        // Back-substitution
        var x = new Array<Float>();
        for (_ in 0...n) x.push(0.0);
        for (i in 0...n) x.push(0.0);
        var i = n - 1;
        while (i >= 0) {
            var sum = b[i];
            for (j in i+1...n) sum -= A[i][j] * x[j];
            x[i] = sum / A[i][i];
            i--;
        }
        x.push(1.0); // h[8]
        return x.slice(0, 9);
    }
}
