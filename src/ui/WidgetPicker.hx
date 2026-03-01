package ui;

import js.html.Element;
import js.Browser;
import widgets.WidgetRegistry;
import util.EventBus;

/**
 * Sidebar panel listing all available widget types.
 * Click to add a widget to the active tab.
 */
class WidgetPicker {
    var panel: Element;
    var bus: EventBus;
    public var isOpen(default, null): Bool = false;

    public function new(bus: EventBus) {
        this.bus = bus;
        buildDOM();
    }

    function buildDOM(): Void {
        panel = Browser.document.createElement("div");
        panel.id = "widget-picker";

        var groups: Map<String, Array<String>> = new Map();
        groups["Display"] = ["NumberDisplay", "TextDisplay", "BooleanBox", "MatchTime"];
        groups["Control"] = ["ToggleButton", "SendableChooser"];
        groups["Graph"]   = ["LineGraph", "Gauge", "GyroWidget"];
        groups["Field"]   = ["FieldWidget", "CameraStream"];
        groups["System"]  = ["SubsystemWidget", "CommandScheduler", "PowerDistribution"];
        groups["Custom"]  = ["AutoAlignWidget"];

        var order = ["Display", "Control", "Graph", "Field", "System", "Custom"];
        for (grp in order) {
            var items = groups[grp];
            if (items == null) continue;

            var title = Browser.document.createElement("div");
            title.className = "picker-section-title";
            title.textContent = grp;
            panel.appendChild(title);

            for (type in items) {
                var item = Browser.document.createElement("div");
                item.className = "picker-item";
                item.textContent = type;
                item.title = "Add " + type;
                var t = type;
                item.addEventListener("click", function(_) {
                    bus.emit("grid:addWidget", { type: t });
                });
                panel.appendChild(item);
            }
        }

        Browser.document.body.appendChild(panel);
    }

    public function toggle(): Void {
        isOpen = !isOpen;
        if (isOpen) panel.classList.add("open");
        else        panel.classList.remove("open");
    }

    public function open(): Void {
        isOpen = true;
        panel.classList.add("open");
    }

    public function close(): Void {
        isOpen = false;
        panel.classList.remove("open");
    }
}
