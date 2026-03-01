package widgets;

import core.TopicStore;
import util.EventBus;

/**
 * Factory registry: widget type name → constructor function.
 */
class WidgetRegistry {
    static var registry: Map<String, TopicStore->EventBus->Widget> = new Map();

    public static function register(type: String, factory: TopicStore->EventBus->Widget): Void {
        registry[type] = factory;
    }

    public static function create(type: String, store: TopicStore, bus: EventBus): Null<Widget> {
        var factory = registry[type];
        if (factory == null) return null;
        return factory(store, bus);
    }

    public static function types(): Array<String> {
        return [for (k in registry.keys()) k];
    }

    /** Called from Main.hx before any widgets are created. */
    public static function registerAll(): Void {
        register("NumberDisplay",    (s,b) -> new NumberDisplay(s,b));
        register("TextDisplay",      (s,b) -> new TextDisplay(s,b));
        register("BooleanBox",       (s,b) -> new BooleanBox(s,b));
        register("ToggleButton",     (s,b) -> new ToggleButton(s,b));
        register("LineGraph",        (s,b) -> new LineGraph(s,b));
        register("Gauge",            (s,b) -> new Gauge(s,b));
        register("GyroWidget",       (s,b) -> new GyroWidget(s,b));
        register("FieldWidget",      (s,b) -> new FieldWidget(s,b));
        register("CameraStream",     (s,b) -> new CameraStream(s,b));
        register("SendableChooser",  (s,b) -> new SendableChooser(s,b));
        register("MatchTime",        (s,b) -> new MatchTime(s,b));
        register("SubsystemWidget",  (s,b) -> new SubsystemWidget(s,b));
        register("CommandScheduler", (s,b) -> new CommandScheduler(s,b));
        register("PowerDistribution",(s,b) -> new PowerDistribution(s,b));
        register("AutoAlignWidget",  (s,b) -> new widgets.autoalign.AutoAlignWidget(s,b));
        register("ShooterTuner",     (s,b) -> new ShooterTunerWidget(s,b));
    }
}
