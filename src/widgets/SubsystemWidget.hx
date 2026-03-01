package widgets;

import js.html.Element;
import core.TopicStore;
import util.EventBus;

class SubsystemWidget extends Widget {
    var listEl: Element;
    var subsystems: Map<String, String> = new Map();

    public function new(store: TopicStore, bus: EventBus) {
        super(store, bus, "SubsystemWidget");
        title = "Subsystems";
    }

    override function buildDOM(container: Element): Void {
        container.className += " subsystem-widget";
        container.style.overflow = "auto";
        listEl = makeEl("div");
        container.appendChild(listEl);
    }

    override public function configure(props: Dynamic): Void {
        if (Reflect.hasField(props, "topic")) {
            var base: String = props.topic;
            ntTopics = [base];
            // Subscribe to all subtopics under the base
            subscribePrefix(base + "/", onNTUpdate);
        }
        if (Reflect.hasField(props, "title")) title = props.title;
    }

    override public function onNTUpdate(topic: String, value: Dynamic): Void {
        // NT4 command-based: /LiveWindow/<SubsystemName>/.command = "CommandName"
        // Extract subsystem name from topic
        var parts = topic.split("/");
        if (parts.length < 3) return;

        // Find .command entries
        if (parts[parts.length-1] == ".command") {
            var subsysName = parts[parts.length-2];
            subsystems[subsysName] = Std.string(value);
            rebuild();
        } else if (parts[parts.length-1] == ".hasCommand") {
            // subsystem exists
            var subsysName = parts[parts.length-2];
            if (!subsystems.exists(subsysName)) {
                subsystems[subsysName] = "";
                rebuild();
            }
        }
    }

    function rebuild(): Void {
        if (listEl == null) return;
        listEl.innerHTML = "";
        for (name => cmd in subsystems) {
            var row = makeEl("div", "sub-row");
            var nameEl = makeEl("span", "sub-name");
            nameEl.textContent = name;
            var cmdEl = makeEl("span", "sub-cmd" + (cmd.length == 0 ? " none" : ""));
            cmdEl.textContent = cmd.length > 0 ? cmd : "—";
            row.appendChild(nameEl);
            row.appendChild(cmdEl);
            listEl.appendChild(row);
        }
    }

    override public function serialize(): Dynamic {
        return { title: title, topic: ntTopics.length > 0 ? ntTopics[0] : "" };
    }
}
