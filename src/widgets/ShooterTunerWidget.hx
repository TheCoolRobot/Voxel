package widgets;

import js.html.Element;
import js.html.InputElement;
import core.TopicStore;
import util.EventBus;

typedef ShotRecord = {
    dist:      Float,   // meters at shot time
    cmdAngle:  Float,   // angle from shooter table
    cmdRpm:    Float,   // RPM from shooter table
    actualRpm: Float,   // measured RPM
    hDev:      Float,   // limelight HDeviation (px)
    vDev:      Float,   // limelight VDeviation (px) — positive = target above crosshair
    scored:    Null<Bool>, // null=awaiting, true=hit, false=miss
    ts:        Float,   // epoch ms
}

typedef Bucket = {
    dist:        Float,
    shots:       Int,
    hits:        Int,
    sumVDevMiss: Float,
    missCount:   Int,
    tableAngle:  Float,
    tableRpm:    Float,
    sugAngle:    Float,   // computed suggestion
    sugRpm:      Float,
}

/**
 * Shooter Table Tuner.
 *
 * Records shots via NT events, groups them by distance into configurable
 * buckets, computes per-bucket accuracy, and derives angle corrections from
 * the Limelight vertical deviation at miss time.  Apply individual or all
 * suggestions to publish an updated shooter table back to NT.
 *
 * Distance is read from either:
 *   • "limelight" mode — formula: (targetHeight-camHeight)/tan(mountAngle+ty)
 *   • "topic"     mode — direct NT double topic
 *
 * Shot detection:  rising edge on firedTopic  (default /Shooter/Fired)
 * Hit  detection:  rising edge on scoredTopic (default /Shooter/NoteScored)
 *                  within hitTimeoutMs of the shot
 */
class ShooterTunerWidget extends Widget {

    // ── NT topics (all configurable) ─────────────────────────────────────────
    var firedTopic:       String = "/Shooter/Fired";
    var scoredTopic:      String = "/Shooter/NoteScored";
    var tableTopic:       String = "/SmartDashboard/ShooterTable";
    var rpmTopic:         String = "/Shooter/FlywheelRPM";
    var hDevTopic:        String = "/AutoAlign/HDeviation";
    var vDevTopic:        String = "/AutoAlign/VDeviation";
    var limelightTyTopic: String = "/limelight/ty";
    var distTopic:        String = "/Drive/DistanceToTarget";

    // ── Distance geometry ─────────────────────────────────────────────────────
    var distSource:    String = "topic";     // "limelight" | "topic"
    var camHeight:     Float  = 0.28;        // m
    var mountAngleDeg: Float  = 25.0;        // degrees above horizontal
    var targetHeight:  Float  = 2.11;        // m (Reefscape speaker opening)

    // ── Test plan ─────────────────────────────────────────────────────────────
    var testFrom:     Float = 2.0;
    var testTo:       Float = 7.0;
    var buckStep:     Float = 0.5;
    var shotsPerDist: Int   = 5;

    // ── Tuning params ─────────────────────────────────────────────────────────
    var kAngle:       Float = 0.25;    // deg / limelight pixel of VDev offset
    var hitTimeoutMs: Float = 1800.0;  // ms after shot to expect NoteScored
    var minShots:     Int   = 3;       // shots before suggestion is computed

    // ── Live values ───────────────────────────────────────────────────────────
    var currentRpm:  Float = 0.0;
    var currentHDev: Float = 0.0;
    var currentVDev: Float = 0.0;
    var currentDist: Float = 0.0;
    var lastFired:   Bool  = false;
    var lastScored:  Bool  = false;

    // ── Session state ─────────────────────────────────────────────────────────
    var recording:    Bool             = false;
    var shotLog:      Array<ShotRecord>= [];
    var buckets:      Map<String,Bucket>= new Map();
    var tableRows:    Array<{dist:Float,angle:Float,rpm:Float}> = [];
    var pendingShot:  Null<ShotRecord> = null;
    var pendingTimer: Null<haxe.Timer> = null;

    // ── DOM refs ──────────────────────────────────────────────────────────────
    var recBtn:       Element;
    var statusLbl:    Element;
    var progressFill: Element;
    var progressLbl:  Element;
    var statsBody:    Element;
    var logBody:      Element;
    // config inputs
    var inpFrom: InputElement; var inpTo:      InputElement;
    var inpStep: InputElement; var inpN:       InputElement;
    var inpK:    InputElement; var inpTimeout: InputElement;

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "ShooterTuner");
        title = "Shooter Tuner";
    }

    // ── DOM ───────────────────────────────────────────────────────────────────
    override function buildDOM(container: Element): Void {
        container.className += " shooter-tuner";

        // Header
        var hdr = mkDiv("st-header");
        var ttl = mkDiv("st-title"); ttl.textContent = "Shooter Table Tuner";
        statusLbl = mkDiv("st-status"); statusLbl.textContent = "Idle";
        recBtn = mkBtn("● Record", toggleRecording, "st-rec-btn");
        hdr.appendChild(ttl); hdr.appendChild(statusLbl); hdr.appendChild(recBtn);
        container.appendChild(hdr);

        // Config strip
        var cfg = mkDiv("st-config");
        inpFrom    = numInp(testFrom);  inpTo    = numInp(testTo);
        inpStep    = numInp(buckStep);  inpN     = numInp(shotsPerDist);
        inpK       = numInp(kAngle);   inpTimeout = numInp(hitTimeoutMs);
        cfg.appendChild(cfgField("From m",    inpFrom,    function(v){ testFrom = v;  rebuildPlan(); }));
        cfg.appendChild(cfgField("To m",      inpTo,      function(v){ testTo   = v;  rebuildPlan(); }));
        cfg.appendChild(cfgField("Step m",    inpStep,    function(v){ buckStep = v;  rebuildBuckets(); rebuildPlan(); }));
        cfg.appendChild(cfgField("Shots/pt",  inpN,       function(v){ shotsPerDist = Std.int(v); rebuildPlan(); }));
        cfg.appendChild(cfgField("kAngle°/px",inpK,       function(v){ kAngle = v;   rebuildBuckets(); }));
        cfg.appendChild(cfgField("Timeout ms",inpTimeout, function(v){ hitTimeoutMs = v; }));
        cfg.appendChild(mkBtn("Apply All", doApplyAll, "st-btn st-apply"));
        cfg.appendChild(mkBtn("Clear",     doClear,    "st-btn"));
        container.appendChild(cfg);

        // Progress bar
        var progRow = mkDiv("st-progress-row");
        progressLbl  = mkDiv("st-progress-lbl"); progressLbl.textContent = "Test progress: 0%";
        var progTrack = mkDiv("st-progress-track");
        progressFill  = mkDiv("st-progress-fill");
        progressFill.style.width = "0%";
        progTrack.appendChild(progressFill);
        progRow.appendChild(progressLbl);
        progRow.appendChild(progTrack);
        container.appendChild(progRow);

        // Stats table
        var st = mkDiv("st-section-title"); st.textContent = "Accuracy by Distance";
        container.appendChild(st);
        var sTable = js.Browser.document.createElement("table");
        sTable.className = "st-table";
        sTable.innerHTML = '<thead><tr>' +
            '<th>Dist</th><th>Shots</th><th class="st-th-bar">Accuracy</th>' +
            '<th>Avg VDev</th><th>Cur°</th><th>Sug°</th>' +
            '<th>Cur RPM</th><th>Sug RPM</th><th></th></tr></thead>';
        statsBody = js.Browser.document.createElement("tbody");
        sTable.appendChild(statsBody);
        container.appendChild(sTable);

        // Shot log
        var lt = mkDiv("st-section-title"); lt.textContent = "Shot Log (last 60)";
        container.appendChild(lt);
        var lTable = js.Browser.document.createElement("table");
        lTable.className = "st-table";
        lTable.innerHTML = '<thead><tr><th>#</th><th>Dist</th><th>Cmd°</th>' +
            '<th>RPM</th><th>VDev</th><th>HDev</th><th>Result</th></tr></thead>';
        logBody = js.Browser.document.createElement("tbody");
        lTable.appendChild(logBody);
        container.appendChild(lTable);

        rebuildPlan();
    }

    // ── Configure ─────────────────────────────────────────────────────────────
    override public function configure(props: Dynamic): Void {
        if (Reflect.hasField(props, "title")) title = props.title;

        inline function s(f:String, d:String):String
            return Reflect.hasField(props,f) ? Std.string(Reflect.field(props,f)) : d;
        inline function n(f:String, d:Float):Float {
            if (!Reflect.hasField(props,f)) return d;
            var v = Std.parseFloat(Std.string(Reflect.field(props,f)));
            return Math.isNaN(v) ? d : v;
        }

        firedTopic       = s("firedTopic",       firedTopic);
        scoredTopic      = s("scoredTopic",       scoredTopic);
        tableTopic       = s("tableTopic",        tableTopic);
        rpmTopic         = s("rpmTopic",          rpmTopic);
        hDevTopic        = s("hDevTopic",         hDevTopic);
        vDevTopic        = s("vDevTopic",         vDevTopic);
        limelightTyTopic = s("limelightTyTopic",  limelightTyTopic);
        distTopic        = s("distTopic",         distTopic);
        distSource       = s("distSource",        distSource);
        camHeight        = n("camHeight",         camHeight);
        mountAngleDeg    = n("mountAngleDeg",     mountAngleDeg);
        targetHeight     = n("targetHeight",      targetHeight);
        testFrom         = n("testFrom",          testFrom);
        testTo           = n("testTo",            testTo);
        buckStep         = n("buckStep",          buckStep);
        shotsPerDist     = Std.int(n("shotsPerDist", shotsPerDist));
        kAngle           = n("kAngle",            kAngle);
        hitTimeoutMs     = n("hitTimeoutMs",      hitTimeoutMs);
        minShots         = Std.int(n("minShots",  minShots));

        // Sync config inputs
        if (inpFrom != null) {
            inpFrom.value = Std.string(testFrom);   inpTo.value   = Std.string(testTo);
            inpStep.value = Std.string(buckStep);   inpN.value    = Std.string(shotsPerDist);
            inpK.value    = Std.string(kAngle);     inpTimeout.value = Std.string(hitTimeoutMs);
        }

        // Re-subscribe to all required topics
        for (fn in unsubFns) fn(); unsubFns = [];
        subscribeTopic(firedTopic,  onNTUpdate);
        subscribeTopic(scoredTopic, onNTUpdate);
        subscribeTopic(tableTopic,  onNTUpdate);
        subscribeTopic(rpmTopic,    onNTUpdate);
        subscribeTopic(hDevTopic,   onNTUpdate);
        subscribeTopic(vDevTopic,   onNTUpdate);
        if (distSource == "limelight") subscribeTopic(limelightTyTopic, onNTUpdate);
        else                           subscribeTopic(distTopic,         onNTUpdate);
    }

    // ── NT updates ────────────────────────────────────────────────────────────
    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        if (topic == rpmTopic)          { currentRpm  = toF(value); return; }
        if (topic == hDevTopic)         { currentHDev = toF(value); return; }
        if (topic == vDevTopic)         { currentVDev = toF(value); return; }
        if (topic == distTopic)         { currentDist = toF(value); return; }
        if (topic == limelightTyTopic)  {
            var ty  = toF(value);
            var rad = (mountAngleDeg + ty) * Math.PI / 180.0;
            if (Math.tan(rad) > 0.001)
                currentDist = (targetHeight - camHeight) / Math.tan(rad);
            return;
        }
        if (topic == tableTopic) { parseTable(value); return; }
        if (topic == firedTopic) {
            var now = toBool(value);
            if (now && !lastFired && recording) onShot();
            lastFired = now;
            return;
        }
        if (topic == scoredTopic) {
            var now = toBool(value);
            if (now && !lastScored) finalizeShot(true);
            lastScored = now;
            return;
        }
    }

    // ── Shot lifecycle ────────────────────────────────────────────────────────
    function onShot(): Void {
        var dist = Math.max(0.1, currentDist);
        var shot: ShotRecord = {
            dist:      Math.round(dist * 100) / 100,
            cmdAngle:  angleAt(dist),
            cmdRpm:    rpmAt(dist),
            actualRpm: currentRpm,
            hDev:      currentHDev,
            vDev:      currentVDev,
            scored:    null,
            ts:        js.lib.Date.now(),
        };
        pendingShot = shot;
        shotLog.unshift(shot);
        if (shotLog.length > 300) shotLog.pop();
        if (pendingTimer != null) pendingTimer.stop();
        pendingTimer = haxe.Timer.delay(function() {
            if (pendingShot != null && pendingShot.scored == null) finalizeShot(false);
        }, Std.int(hitTimeoutMs));
        setStatus('Fired @ ${shot.dist}m');
        renderLog();
    }

    function finalizeShot(hit: Bool): Void {
        if (pendingTimer != null) { pendingTimer.stop(); pendingTimer = null; }
        if (pendingShot == null) return;
        pendingShot.scored = hit;
        pendingShot = null;
        rebuildBuckets();
        rebuildPlan();
        renderStats();
        renderLog();
        setStatus(hit ? "✓ HIT" : "✗ MISS");
    }

    // ── Bucketing & auto-tune ─────────────────────────────────────────────────
    inline function snapDist(d: Float): Float
        return Math.round(d / buckStep) * buckStep;

    function bucketKey(d: Float): String
        return Std.string(Math.round(snapDist(d) * 10) / 10);

    function rebuildBuckets(): Void {
        buckets = new Map();
        for (shot in shotLog) {
            if (shot.scored == null) continue;
            var key = bucketKey(shot.dist);
            var bd  = Std.parseFloat(key);
            if (!buckets.exists(key)) {
                buckets[key] = {
                    dist: bd, shots: 0, hits: 0,
                    sumVDevMiss: 0.0, missCount: 0,
                    tableAngle: angleAt(bd), tableRpm: rpmAt(bd),
                    sugAngle: angleAt(bd),   sugRpm:   rpmAt(bd),
                };
            }
            var b = buckets[key];
            b.shots++;
            if (shot.scored == true) b.hits++;
            else { b.sumVDevMiss += shot.vDev; b.missCount++; }
        }
        // Compute angle suggestions from average VDev on misses
        for (_ => b in buckets) {
            if (b.shots < minShots || b.missCount < 2) continue;
            var avgVDev = b.sumVDevMiss / b.missCount;
            // VDev > 0 → target is above crosshair → note fell short → increase angle
            b.sugAngle = Math.round((b.tableAngle + avgVDev * kAngle) * 10) / 10;
        }
    }

    // ── Progress bar ──────────────────────────────────────────────────────────
    function testTargets(): Array<Float> {
        var out: Array<Float> = [];
        var d = testFrom;
        while (d <= testTo + 0.001) { out.push(Math.round(d * 10) / 10); d += buckStep; }
        return out;
    }

    function rebuildPlan(): Void {
        if (progressFill == null) return;
        var targets = testTargets();
        if (targets.length == 0) return;
        var done = 0;
        for (t in targets) {
            var k = bucketKey(t);
            if (buckets.exists(k) && buckets[k].shots >= shotsPerDist) done++;
        }
        var pct = Std.int(done / targets.length * 100);
        progressFill.style.width = '${pct}%';
        progressFill.style.background = pct >= 100 ? "var(--green)" : "var(--cyan)";
        progressLbl.textContent = 'Test progress: ${done}/${targets.length} distances (${pct}%)';
        renderStats();  // re-render so pending rows appear
    }

    // ── Render stats ──────────────────────────────────────────────────────────
    function renderStats(): Void {
        if (statsBody == null) return;
        statsBody.innerHTML = "";
        var targets = testTargets();

        // Collect all keys (test plan + any off-plan buckets)
        var allKeys: Array<String> = [];
        var seen = new Map<String, Bool>();
        for (t in targets) {
            var k = bucketKey(t);
            if (!seen.exists(k)) { seen[k] = true; allKeys.push(k); }
        }
        for (k in buckets.keys()) {
            if (!seen.exists(k)) { seen[k] = true; allKeys.push(k); }
        }
        allKeys.sort(function(a, b) return Std.parseFloat(a) < Std.parseFloat(b) ? -1 : 1);

        for (key in allKeys) {
            var b = buckets[key];
            var tr = js.Browser.document.createElement("tr");

            if (b == null) {
                // Planned distance, no shots yet
                tr.className = "st-planned";
                tr.innerHTML = '<td>${Std.parseFloat(key)}m</td>' +
                    '<td colspan="8" class="st-awaiting">0/${shotsPerDist} — drive here and shoot</td>';
                statsBody.appendChild(tr);
                continue;
            }

            var acc = b.shots > 0 ? b.hits / b.shots : 0.0;
            var pct = Std.int(acc * 100);
            var avgVDev = b.missCount > 0 ? Math.round(b.sumVDevMiss / b.missCount * 10) / 10 : 0.0;
            var hasSug  = b.shots >= minShots && b.sugAngle != b.tableAngle;
            var isComplete = b.shots >= shotsPerDist;

            if (hasSug)          tr.className = "st-changed";
            else if (isComplete) tr.className = "st-done";

            var barColor = pct >= 80 ? "var(--green)" : pct >= 50 ? "var(--yellow)" : "var(--red)";

            function addTd(txt:String, ?cls:String): Void {
                var c = js.Browser.document.createElement("td");
                if (cls != null) c.className = cls;
                c.textContent = txt;
                tr.appendChild(c);
            }

            addTd(b.dist + "m");
            addTd('${b.hits}/${b.shots}');

            // Accuracy bar
            var barTd = js.Browser.document.createElement("td");
            barTd.innerHTML = '<div class="st-bar-wrap">' +
                '<div class="st-bar-fill" style="width:${pct}%;background:${barColor}"></div>' +
                '<span class="st-bar-lbl">${pct}%</span></div>';
            tr.appendChild(barTd);

            var vDevCls = avgVDev > 0.8 ? "st-vdev-hi" : (avgVDev < -0.8 ? "st-vdev-lo" : "");
            addTd(b.missCount > 0 ? Std.string(avgVDev) + "px" : "—", vDevCls);
            addTd(b.tableAngle + "°");
            addTd(hasSug ? b.sugAngle + "°" : "—", hasSug ? "st-sug" : "");
            addTd(Std.string(Std.int(b.tableRpm)));
            addTd(hasSug ? Std.string(Std.int(b.sugRpm)) : "—", hasSug ? "st-sug" : "");

            var actTd = js.Browser.document.createElement("td");
            if (hasSug) {
                var bd = b.dist;
                actTd.appendChild(mkBtn("Apply", function() { applyBucket(bd); }, "st-btn st-apply"));
            }
            tr.appendChild(actTd);
            statsBody.appendChild(tr);
        }

        if (allKeys.length == 0) {
            var empty = js.Browser.document.createElement("tr");
            empty.innerHTML = '<td colspan="9" class="st-empty">Enable recording and start shooting.</td>';
            statsBody.appendChild(empty);
        }
    }

    function renderLog(): Void {
        if (logBody == null) return;
        logBody.innerHTML = "";
        var shown = shotLog.slice(0, 60);
        for (i in 0...shown.length) {
            var s = shown[i];
            var tr = js.Browser.document.createElement("tr");
            tr.className = s.scored == null ? "st-pending" : (s.scored == true ? "st-hit-row" : "st-miss-row");
            var resCls = s.scored == null ? "" : (s.scored == true ? "st-hit-lbl" : "st-miss-lbl");
            var resText = s.scored == null ? "…" : (s.scored == true ? "✓ HIT" : "✗ MISS");
            tr.innerHTML = '<td>${shotLog.length - i}</td>' +
                '<td>${Math.round(s.dist*10)/10}m</td>' +
                '<td>${Math.round(s.cmdAngle*10)/10}°</td>' +
                '<td>${Std.int(s.actualRpm)}</td>' +
                '<td>${Math.round(s.vDev*10)/10}</td>' +
                '<td>${Math.round(s.hDev*10)/10}</td>' +
                '<td class="${resCls}">${resText}</td>';
            logBody.appendChild(tr);
        }
    }

    // ── Table lookup helpers ──────────────────────────────────────────────────
    function angleAt(dist: Float): Float {
        if (tableRows.length == 0) return 40.0;
        var best = tableRows[0];
        for (r in tableRows) if (Math.abs(r.dist - dist) < Math.abs(best.dist - dist)) best = r;
        return best.angle;
    }

    function rpmAt(dist: Float): Float {
        if (tableRows.length == 0) return 3000.0;
        var best = tableRows[0];
        for (r in tableRows) if (Math.abs(r.dist - dist) < Math.abs(best.dist - dist)) best = r;
        return best.rpm;
    }

    function parseTable(v: Dynamic): Void {
        try {
            var data: Array<Dynamic> = Std.isOfType(v, String) ? haxe.Json.parse(v) : v;
            tableRows = [];
            for (item in data)
                tableRows.push({
                    dist:  toF(item.dist  != null ? item.dist  : 0.0),
                    angle: toF(item.angle != null ? item.angle : 40.0),
                    rpm:   toF(item.rpm   != null ? item.rpm   : 3000.0),
                });
            tableRows.sort(function(a, b) return a.dist < b.dist ? -1 : 1);
            rebuildBuckets();
            renderStats();
        } catch (_:Dynamic) {}
    }

    // ── Apply suggestions ─────────────────────────────────────────────────────
    function applyBucket(dist: Float): Void {
        var key = bucketKey(dist);
        if (!buckets.exists(key)) return;
        var b = buckets[key];
        var found = false;
        for (r in tableRows) {
            if (Math.abs(r.dist - dist) <= buckStep * 0.6) {
                r.angle = b.sugAngle; r.rpm = b.sugRpm; found = true; break;
            }
        }
        if (!found) {
            tableRows.push({ dist: Math.round(dist*10)/10, angle: b.sugAngle, rpm: b.sugRpm });
            tableRows.sort(function(a, b) return a.dist < b.dist ? -1 : 1);
        }
        b.tableAngle = b.sugAngle; b.tableRpm = b.sugRpm;
        publish(tableTopic, haxe.Json.stringify(tableRows), "string");
        renderStats();
        setStatus('Applied @ ${dist}m');
    }

    function doApplyAll(): Void {
        for (_ => b in buckets)
            if (b.shots >= minShots && b.sugAngle != b.tableAngle)
                applyBucket(b.dist);
        setStatus("Applied all suggestions");
    }

    function doClear(): Void {
        shotLog = []; buckets = new Map();
        renderStats(); renderLog(); rebuildPlan();
        setStatus("Cleared");
    }

    // ── Controls ──────────────────────────────────────────────────────────────
    function toggleRecording(): Void {
        recording = !recording;
        if (recording) {
            recBtn.textContent = "■ Stop";
            cast(recBtn, js.html.Element).classList.add("active");
            setStatus("Recording…");
        } else {
            recBtn.textContent = "● Record";
            cast(recBtn, js.html.Element).classList.remove("active");
            setStatus("Stopped");
        }
    }

    function setStatus(msg: String): Void {
        if (statusLbl != null) statusLbl.textContent = msg;
    }

    override public function destroy(): Void {
        super.destroy();
        if (pendingTimer != null) { pendingTimer.stop(); pendingTimer = null; }
    }

    // ── DOM helpers ───────────────────────────────────────────────────────────
    function mkDiv(cls: String): Element {
        var e = js.Browser.document.createElement("div");
        if (cls.length > 0) e.className = cls;
        return e;
    }

    function mkBtn(label: String, cb: Void->Void, cls: String = "st-btn"): Element {
        var b = js.Browser.document.createElement("button");
        b.className = cls; b.textContent = label;
        b.addEventListener("click", function(_) cb());
        return b;
    }

    function numInp(def: Float): InputElement {
        var i = cast(js.Browser.document.createElement("input"), InputElement);
        i.type = "number"; i.step = "0.1"; i.value = Std.string(def);
        return i;
    }

    function cfgField(label: String, inp: InputElement, cb: Float->Void): Element {
        var w = mkDiv("st-cfg-field");
        var l = js.Browser.document.createElement("label"); l.textContent = label;
        w.appendChild(l); w.appendChild(inp);
        inp.addEventListener("change", function(_) {
            var v = Std.parseFloat(inp.value);
            if (!Math.isNaN(v)) cb(v);
        });
        return w;
    }

    inline function toF(v: Dynamic): Float {
        var f = Std.parseFloat(Std.string(v));
        return Math.isNaN(f) ? 0.0 : f;
    }

    inline function toBool(v: Dynamic): Bool
        return v == true || v == 1 || Std.string(v) == "true";

    // ── Serialize ─────────────────────────────────────────────────────────────
    override public function serialize(): Dynamic {
        var o = super.serialize();
        o.firedTopic       = firedTopic;    o.scoredTopic    = scoredTopic;
        o.tableTopic       = tableTopic;    o.rpmTopic       = rpmTopic;
        o.hDevTopic        = hDevTopic;     o.vDevTopic      = vDevTopic;
        o.limelightTyTopic = limelightTyTopic; o.distTopic   = distTopic;
        o.distSource       = distSource;    o.camHeight      = camHeight;
        o.mountAngleDeg    = mountAngleDeg; o.targetHeight   = targetHeight;
        o.testFrom         = testFrom;      o.testTo         = testTo;
        o.buckStep         = buckStep;      o.shotsPerDist   = shotsPerDist;
        o.kAngle           = kAngle;        o.hitTimeoutMs   = hitTimeoutMs;
        o.minShots         = minShots;
        return o;
    }
}
