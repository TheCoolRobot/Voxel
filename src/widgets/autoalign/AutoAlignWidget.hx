package widgets.autoalign;

import js.html.Element;
import core.TopicStore;
import util.EventBus;
import widgets.Widget;

/**
 * Master composite widget:
 *  Row 1: Limelight MJPEG + path canvas overlay
 *  Row 2: H deviation | V deviation | Flywheel RPM gauge
 *  Row 3: Shooter lookup table (editable, NT read/write)
 */
class AutoAlignWidget extends Widget {
    // Sub-components
    var cameraOverlay: CameraOverlay;
    var hDeviation: DeviationIndicator;
    var vDeviation: DeviationIndicator;
    var ferryGauge: FerryGauge;
    var shooterEditor: ShooterLookupEditor;
    var projector: PathProjector;

    // NT topic config
    var cameraUrl: String = "";
    var hDeviationTopic: String = "/AutoAlign/HDeviation";
    var vDeviationTopic: String = "/AutoAlign/VDeviation";
    var rpmTopic: String = "/Shooter/FlywheelRPM";
    var rpmTargetTopic: String = "/Shooter/TargetRPM";
    var shooterTableTopic: String = "/SmartDashboard/ShooterTable";
    var pathTopic: String = "/AutoAlign/PathPoints";

    // RAF for gauge rendering
    var rafId: Int = -1;

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "AutoAlignWidget");
        title = "AutoAlign / Ferry";
        projector = new PathProjector();
    }

    override function buildDOM(container: Element): Void {
        container.className += " autoalign-widget";
        container.style.padding = "0";

        // Row 1: Camera + path overlay
        cameraOverlay = new CameraOverlay(projector);
        container.appendChild(cameraOverlay.element);

        // Row 2: Indicators
        var indRow = js.Browser.document.createElement("div");
        indRow.className = "autoalign-indicators-row";

        hDeviation = new DeviationIndicator("H Deviation", false, 100.0, "px");
        vDeviation = new DeviationIndicator("V Deviation", true,  100.0, "px");
        ferryGauge = new FerryGauge();

        indRow.appendChild(hDeviation.element);
        indRow.appendChild(vDeviation.element);
        indRow.appendChild(ferryGauge.element);
        container.appendChild(indRow);

        // Row 3: Shooter table
        shooterEditor = new ShooterLookupEditor(bus, onPublish);
        container.appendChild(shooterEditor.element);

        startGaugeRender();
    }

    override public function configure(props: Dynamic): Void {
        if (Reflect.hasField(props, "title"))              title = props.title;
        if (Reflect.hasField(props, "cameraUrl"))          cameraUrl = props.cameraUrl;
        if (Reflect.hasField(props, "hDeviationTopic"))    hDeviationTopic = props.hDeviationTopic;
        if (Reflect.hasField(props, "vDeviationTopic"))    vDeviationTopic = props.vDeviationTopic;
        if (Reflect.hasField(props, "rpmTopic"))           rpmTopic = props.rpmTopic;
        if (Reflect.hasField(props, "rpmTargetTopic"))     rpmTargetTopic = props.rpmTargetTopic;
        if (Reflect.hasField(props, "shooterTableTopic"))  shooterTableTopic = props.shooterTableTopic;
        if (Reflect.hasField(props, "pathTopic"))          pathTopic = props.pathTopic;

        projector.configure(props);
        if (cameraOverlay != null) cameraOverlay.setUrl(cameraUrl);
        if (shooterEditor != null) shooterEditor.setTopic(shooterTableTopic);

        // Clear old subscriptions and re-subscribe
        for (fn in unsubFns) fn();
        unsubFns = [];

        subscribeTopic(hDeviationTopic, function(_, v) {
            hDeviation.setValue(v);
        });
        subscribeTopic(vDeviationTopic, function(_, v) {
            vDeviation.setValue(v);
        });
        subscribeTopic(rpmTopic, function(_, v) {
            ferryGauge.actualRpm = v;
        });
        subscribeTopic(rpmTargetTopic, function(_, v) {
            ferryGauge.targetRpm = v;
        });
        subscribeTopic(shooterTableTopic, function(_, v) {
            shooterEditor.loadFromNT(v);
        });
        subscribeTopic(pathTopic, function(_, v) {
            var pts = projector.project(v,
                cameraOverlay.element.clientWidth,
                cameraOverlay.element.clientHeight);
            cameraOverlay.setPathPoints(pts);
        });
    }

    function onPublish(topic: String, value: Dynamic, type: String): Void {
        bus.emit("nt:publish", { topic: topic, value: value, type: type });
    }

    function startGaugeRender(): Void {
        rafId = js.Browser.window.requestAnimationFrame(function(_) {
            if (ferryGauge != null) ferryGauge.render();
            startGaugeRender();
        });
    }

    override public function onResize(): Void {
        if (cameraOverlay != null) cameraOverlay.redraw();
        if (ferryGauge != null) ferryGauge.render();
    }

    override public function destroy(): Void {
        super.destroy();
        if (rafId >= 0) js.Browser.window.cancelAnimationFrame(rafId);
    }

    override public function serialize(): Dynamic {
        return {
            title:              title,
            cameraUrl:          cameraUrl,
            hDeviationTopic:    hDeviationTopic,
            vDeviationTopic:    vDeviationTopic,
            rpmTopic:           rpmTopic,
            rpmTargetTopic:     rpmTargetTopic,
            shooterTableTopic:  shooterTableTopic,
            pathTopic:          pathTopic,
            pathMode:           (projector.mode : String)
        };
    }
}
