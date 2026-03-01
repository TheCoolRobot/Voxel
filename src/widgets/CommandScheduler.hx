package widgets;

import js.html.Element;
import core.TopicStore;
import util.EventBus;

class CommandScheduler extends Widget {
    var listEl: Element;
    var commands: Array<String> = [];

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "CommandScheduler");
        title = "Commands";
    }

    override function buildDOM(container: Element): Void {
        container.className += " command-scheduler";
        listEl = makeEl("div", "cmd-list");
        container.appendChild(listEl);
    }

    override public function configure(props: Dynamic): Void {
        super.configure(props);
        // Also subscribe to the names subtopic
        if (ntTopics.length > 0) {
            var base = ntTopics[0];
            subscribeTopic(base + "/Names", onNTUpdate);
            subscribeTopic(base + "/Running", onNTUpdate);
        }
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        if (Std.isOfType(value, Array)) {
            commands = cast value;
        } else if (Std.isOfType(value, String)) {
            // Try to parse as JSON array
            try { commands = haxe.Json.parse(value); } catch (_) {}
        }
        rebuild();
    }

    function rebuild(): Void {
        if (listEl == null) return;
        listEl.innerHTML = "";
        if (commands.length == 0) {
            var empty = makeEl("div");
            empty.style.cssText = "color:var(--text-dim);font-size:12px;font-style:italic;";
            empty.textContent = "No running commands";
            listEl.appendChild(empty);
            return;
        }
        for (cmd in commands) {
            var item = makeEl("div", "cmd-item");
            item.textContent = cmd;
            listEl.appendChild(item);
        }
    }
}
