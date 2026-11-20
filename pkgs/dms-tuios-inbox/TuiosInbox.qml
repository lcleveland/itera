// TUIOS in the dank bar: the Inbox (what agents wait on you for, in every
// session) and the agents themselves.
//
// - Pill: the Inbox count, coloured by the most urgent item, and how many agents
//   are working; a muted icon when both are zero, since the popout is useful then too.
// - Popout: Inbox cards that answer a question or a held approval, snooze for an
//   hour, or close; agent rows with state, cost and last message, whose recap
//   shows on hover; a keep-awake toggle; a field that starts a new agent.
//   Clicking a card or row focuses its pane and raises the terminal.
// - Notifications: a new item that blocks an agent, or an errored agent, posts a
//   desktop notification with the same answers; a finished turn posts one too.
//   DMS times the popups; clicking one, or its entry in the notification centre,
//   focuses the pane. tuios's own agent popups are off
//   when this widget is on (modules/hjem/programs/tuios.nix).
//
// Live without polling: `tuios subscribe` prints a line per Inbox or agent-state
// change, and each re-reads the lists. If the daemon is down, it is retried.
//
// Acting for the person: tuios takes answers, closes and snoozes only from the
// person. The widget holds the person's presence (`attach-presence`, made for
// programs outside every pane) on its own socket and acts only on a click.
// An on-screen prompt (an approval or question tuios does not hold, such as one
// too long for a line) is read with `peek-prompt` and answered with `respond`,
// with the actions its rule declares. Plans are not answered here: they need
// reading, so their cards jump to the pane.
//
// pluginData (modules/nixos/desktop/tuios.nix): tuios, notifySend, agent (the
// harness the new-agent field starts; empty hides the field).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Modules.Plugins
import qs.Widgets
import qs.DCommon.Widgets

PluginComponent {
    id: root

    readonly property string tuios: pluginData.tuios ?? "tuios"
    readonly property string notifySend: pluginData.notifySend ?? "notify-send"
    readonly property string agentCommand: pluginData.agent ?? ""

    property var items: []
    property var agents: []
    property string keepAwake: "off"
    // A pane reports done while its subagents still run (tuios --skill), so
    // running subagents count as work.
    function busy(a) {
        return a.state === "working" || (a.subagents ?? 0) > 0;
    }
    readonly property int working: agents.filter(a => busy(a)).length

    // The agent is blocked on these; errored is worse, the rest can wait.
    // Colours are the look's roles: teal accent (Theme.primary) for running,
    // coral tertiary (Theme.tertiary) for "needs you", error red for errored.
    readonly property var blocking: ["approval", "plan", "question", "ask"]
    function kindColor(kind) {
        if (kind === "errored")
            return Theme.error;
        if (blocking.includes(kind))
            return Theme.tertiary;
        return Theme.surfaceVariantText;
    }
    // Running is the look's teal accent; an agent waiting on you takes its coral
    // tertiary, so the two read apart.
    function agentColor(a) {
        if (a.state === "errored")
            return Theme.error;
        if (a.state === "needs_input")
            return Theme.tertiary;
        if (busy(a))
            return Theme.primary;
        return Theme.surfaceVariantText;
    }
    readonly property color statusColor: items.some(i => i.kind === "errored") ? Theme.error : items.some(i => blocking.includes(i.kind)) ? Theme.tertiary : Theme.surfaceVariantText

    // What a card can answer in place: an ask's options, a held approval's
    // decisions. Everything else answers in the pane.
    readonly property var decisionLabels: ({ once: "Allow", always: "Always", deny: "Deny", ask: "In pane", approve: "Allow", approve_always: "Always" })
    // On-screen prompts need a peek first; see peek().
    function onScreen(item) {
        return (item.kind === "approval" || item.kind === "question") && !item.request_id;
    }
    property var peeks: ({})
    function answers(item) {
        if (onScreen(item)) {
            const p = peeks[item.id];
            if (!p?.answerable)
                return [];
            // choose and text need the option list or typing: answered in the pane.
            return p.actions.filter(a => ["approve", "approve_always", "deny"].includes(a)).map(a => ({
                label: decisionLabels[a],
                verb: "respond",
                params: Object.assign({ session: item.session, window: item.window, action: a, prompt_id: p.prompt_id }, a === "deny" ? {} : { risk_ack: item.risk ?? [] })
            }));
        }
        if (item.kind === "ask")
            return (item.options ?? []).map(o => ({ label: o, verb: "answer-ask", params: { request_id: item.request_id, answer: o } }));
        if (item.kind === "approval" && item.request_id)
            return (item.options ?? ["once", "always", "deny"]).map(d => ({
                label: decisionLabels[d] ?? d,
                verb: "reply-approval",
                // An allow names the summary and the risks shown on the card.
                params: { request_id: item.request_id, decision: d, summary: item.summary, risk_ack: item.risk ?? [] }
            }));
        return [];
    }

    onItemsChanged: {
        for (const item of items)
            if (onScreen(item) && !(item.id in peeks))
                peek(item);
        notifyNew();
    }
    // Read an on-screen prompt's answers; its notification waits for this.
    function peek(item) {
        peeks[item.id] = null;
        peekProcess.createObject(root, { item: item, command: [tuios, "peek-prompt", "-s", item.session, "-w", item.window, "--json"], running: true });
    }
    Component {
        id: peekProcess
        Process {
            property var item
            stdout: StdioCollector {
                id: peekOutput
            }
            onExited: {
                let d = null;
                try {
                    d = JSON.parse(peekOutput.text);
                } catch (e) {}
                const next = Object.assign({}, root.peeks);
                next[item.id] = d ?? { answerable: false };
                root.peeks = next;
                root.notifyNew();
                destroy();
            }
        }
    }

    // A change during a read re-reads once it ends, so none is missed.
    property bool stale: false
    function refresh() {
        if (listProcess.running)
            stale = true;
        else
            listProcess.running = true;
    }

    function jump(target) {
        // Focus the pane (switching workspace); if a pane is zoomed it would
        // hide the target, so zoom the target instead. Unzoomed layouts stay.
        // shortcut: matches a zoomed pane on any workspace; upgrade to a
        // per-workspace check if that ever zooms a jump that didn't need it.
        Quickshell.execDetached(["sh", "-c", 't="$3"; "$t" focus-window "$1" -s "$2" && if "$t" list-windows -s "$2" --json | grep -q \'"zoomed": true\'; then "$t" zoom-window -w "$1" -s "$2" --on; fi', "jump", target.window, target.session, tuios]);
        // shortcut: raises the first WezTerm window (the terminal battery's); a
        // tuios client in another terminal is focused inside tuios but not raised.
        const term = ToplevelManager.toplevels.values.find(t => t.appId === "org.wezfurlong.wezterm");
        if (term)
            term.activate();
        closePopout();
    }

    // Private Processes, not Proc.runCommand: one instance per bar, and Proc
    // collapses same-id commands onto the last caller (see IteraUpdate.qml).
    Process {
        id: listProcess
        command: ["sh", "-c", 't="$1"; i=$("$t" list-attention --json 2>/dev/null) || i=null; a=$("$t" list-agents --all-sessions --json 2>/dev/null) || a=null; k=$("$t" keep-awake --json 2>/dev/null) || k=null; printf \'{"inbox":%s,"agents":%s,"awake":%s}\' "${i:-null}" "${a:-null}" "${k:-null}"', "list", root.tuios]
        stdout: StdioCollector {
            id: listOutput
        }
        onExited: {
            let d = null;
            try {
                d = JSON.parse(listOutput.text);
            } catch (e) {}
            root.agents = d?.agents?.agents ?? [];
            root.keepAwake = d?.awake?.mode ?? "off";
            root.items = d?.inbox?.items ?? [];
            if (root.stale) {
                root.stale = false;
                running = true;
            }
        }
    }

    Process {
        id: subscribeProcess
        // agent-activity fires on every tool call; only subagent starts and stops
        // change what the widget shows.
        command: [root.tuios, "subscribe", "--types", "attention,agent-state,agent-activity"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                if (line.includes('"type":"agent-activity"') && !line.includes('"kind":"subagent_'))
                    return;
                root.refresh();
            }
        }
        onExited: retry.start()
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: subscribeProcess.running = true
    }

    // The person's presence: connected on the first action, kept open (the nonce
    // lives as long as the connection), and re-made after the daemon restarts.
    property string nonce: ""
    property var pending: []
    property int requestId: 1
    property int presenceRequest: 0
    function send(verb, params) {
        presence.write(JSON.stringify({ id: ++requestId, verb: verb, params: params }) + "\n");
        presence.flush();
        return requestId;
    }
    function asPerson(verb, params) {
        if (nonce !== "") {
            send(verb, Object.assign({ human_nonce: nonce }, params));
            return;
        }
        pending.push({ verb: verb, params: params });
        if (!presence.connected)
            presence.connected = true;
    }
    Socket {
        id: presence
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/tuios/tuios.sock"
        onConnectedChanged: {
            if (connected)
                root.presenceRequest = root.send("attach-presence", {});
            else
                root.nonce = "";
        }
        parser: SplitParser {
            onRead: line => {
                let r = null;
                try {
                    r = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (r.error)
                    console.warn("tuiosInbox: " + line);
                if (r.id !== root.presenceRequest)
                    return;
                // Reply envelope not documented; take the nonce wherever it sits.
                root.nonce = r.result?.human_nonce ?? r.data?.human_nonce ?? r.human_nonce ?? "";
                const queued = root.pending;
                root.pending = [];
                if (root.nonce !== "")
                    for (const p of queued)
                        root.asPerson(p.verb, p.params);
            }
        }
    }

    // Notifications: one bar posts them (each bar runs its own copy of this
    // widget), only for items that appeared since the widget started.
    readonly property bool notifier: parentScreen?.name === Quickshell.screens[0]?.name
    property var notified: null
    // The person is already looking at the item's pane: the terminal is the
    // active window and tuios has that pane focused. Claude's own menus (/mcp)
    // read as needs_input for a moment, so this also keeps them quiet.
    // shortcut: the terminal is WezTerm (the terminal battery's), as in jump().
    function watching(item) {
        return ToplevelManager.activeToplevel?.appId === "org.wezfurlong.wezterm" && agents.some(a => a.window_id === item.window && a.focused);
    }
    function notifyNew() {
        const first = notified === null;
        if (first)
            notified = {};
        for (const item of items) {
            // An on-screen prompt waits for its peek, so its notification has buttons.
            if (notified[item.id] || (!first && onScreen(item) && !peeks[item.id]))
                continue;
            notified[item.id] = true;
            const urgent = blocking.includes(item.kind) || item.kind === "errored";
            if (first || !notifier || !(urgent || item.kind === "finished") || watching(item))
                continue;
            const acts = answers(item);
            // No -t: notify-send stops listening when its own timeout ends, while DMS
            // keeps the notification, so a later click went nowhere. DMS times the
            // popup (5 s by default) and keeps it in the centre; a click on either,
            // the "default" action, still reaches us.
            // shortcut: each notify-send waits until its notification is clicked or
            // cleared; fine for a handful, revisit if the centre is never cleared.
            let cmd = [notifySend, "-a", "TUIOS", "-A", "default=Open"];
            acts.forEach((a, n) => cmd.push("-A", n + "=" + a.label));
            cmd.push((item.name || item.session) + " · " + item.kind, item.summary ?? "");
            notification.createObject(root, { item: item, acts: acts, command: cmd, running: true });
        }
    }
    Component {
        id: notification
        // notify-send -A waits for the notification to close and prints the action.
        Process {
            property var item
            property var acts
            stdout: StdioCollector {
                id: picked
            }
            onExited: {
                const a = picked.text.trim();
                if (a === "default")
                    root.jump(item);
                else if (acts[a])
                    root.asPerson(acts[a].verb, acts[a].params);
                destroy();
            }
        }
    }

    // Recap of the hovered agent's last hour, read after a short hover.
    property var recapFor: null
    property string recapText: ""
    Timer {
        id: recapDelay
        interval: 400
        onTriggered: if (root.recapFor && !recapProcess.running) {
            recapProcess.command = [root.tuios, "agent-log", "-s", root.recapFor.session, "-w", root.recapFor.window_id, "--since", "1h", "--recap"];
            recapProcess.running = true;
        }
    }
    Process {
        id: recapProcess
        stdout: StdioCollector {
            id: recapOutput
        }
        // A recap that lands after the hover ended or moved on is dropped; a moved
        // hover reads the new row's.
        onExited: {
            const asked = command[command.indexOf("-w") + 1];
            if (root.recapFor && root.recapFor.window_id !== asked) {
                root.recapText = "";
                recapDelay.restart();
                return;
            }
            root.recapText = root.recapFor ? recapOutput.text.trim() : "";
        }
    }

    Process {
        id: startProcess
        onExited: root.refresh()
    }

    Process {
        id: keepAwakeProcess
        onExited: root.refresh()
    }

    // Sizes shared by the cards and popoutHeight.
    readonly property int cardHeight: 56
    readonly property int buttonsHeight: 34
    readonly property int agentHeight: 44
    readonly property int subagentHeight: 17
    function agentRowHeight(a) {
        return agentHeight + (a.subagent_list?.length ?? 0) * subagentHeight;
    }
    popoutWidth: 460
    popoutHeight: Math.min(820, 230 + items.reduce((h, i) => h + cardHeight + (answers(i).length ? buttonsHeight : 0) + Theme.spacingXS, 0) + agents.reduce((h, a) => h + agentRowHeight(a) + Theme.spacingXS, 0) + (recapText !== "" ? 110 : 0) + (agentCommand !== "" ? 56 : 0))

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            Row {
                spacing: Theme.spacingXS
                visible: root.items.length > 0
                anchors.verticalCenter: parent.verticalCenter
                DIcon {
                    name: "inbox"
                    size: root.iconSize
                    color: root.statusColor
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: root.items.length
                    color: root.statusColor
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Row {
                spacing: Theme.spacingXS
                // Also the quiet state: a muted icon alone.
                visible: root.working > 0 || root.items.length === 0
                anchors.verticalCenter: parent.verticalCenter
                DIcon {
                    name: "smart_toy"
                    size: root.iconSize
                    color: root.working > 0 ? Theme.primary : Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    visible: root.working > 0
                    text: root.working
                    color: Theme.primary
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            DIcon {
                name: root.items.length > 0 ? "inbox" : "smart_toy"
                size: root.iconSize
                color: root.items.length > 0 ? root.statusColor : Theme.primary
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.items.length > 0 ? root.items.length : root.working
                visible: root.items.length > 0 || root.working > 0
                color: root.items.length > 0 ? root.statusColor : Theme.primary
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // A small round icon button, for the card and header actions.
    component IconButton: Rectangle {
        property string icon
        property color iconColor: Theme.surfaceVariantText
        signal clicked
        width: 28
        height: 28
        radius: 14
        color: area.containsMouse ? Theme.surfaceContainerHighest : "transparent"
        DIcon {
            anchors.centerIn: parent
            name: parent.icon
            size: Theme.iconSizeSmall
            color: area.containsMouse ? Theme.surfaceText : parent.iconColor
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }

    component SectionLabel: StyledText {
        width: parent.width
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
    }

    popoutContent: Component {
        PopoutComponent {
            width: parent ? parent.width : 0
            headerText: "TUIOS"
            detailsText: root.items.length + " waiting · " + root.working + " working"
            showCloseButton: false

            headerActions: Component {
                IconButton {
                    icon: "coffee"
                    iconColor: root.keepAwake === "agents" ? Theme.primary : Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                    // Keep the machine awake while agents work; tuios saves it.
                    onClicked: {
                        keepAwakeProcess.command = [root.tuios, "keep-awake", root.keepAwake === "agents" ? "off" : "agents"];
                        keepAwakeProcess.running = true;
                    }
                }
            }

            Flickable {
                width: parent.width
                height: Math.min(contentHeight, 680)
                contentHeight: content.implicitHeight
                clip: true

                Column {
                    id: content
                    width: parent.width
                    spacing: Theme.spacingXS

                    SectionLabel {
                        text: "Inbox · " + (root.items.length > 0 ? root.items.length + " waiting" : "nothing waiting")
                    }

                    Repeater {
                        model: root.items

                        // The card style of the itera update widget.
                        StyledRect {
                            id: card
                            readonly property var acts: root.answers(modelData)
                            width: content.width
                            height: root.cardHeight + (acts.length ? root.buttonsHeight : 0)
                            radius: Theme.cornerRadius
                            color: rowArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.1)
                            border.width: 1

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.jump(modelData)
                            }

                            // A bar in the item's colour marks its kind at a glance.
                            Rectangle {
                                width: 3
                                radius: 1.5
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                anchors.margins: Theme.spacingS
                                color: root.kindColor(modelData.kind)
                            }

                            Column {
                                x: Theme.spacingM + 3
                                y: (root.cardHeight - implicitHeight) / 2
                                width: parent.width - x - Theme.spacingM - 60
                                spacing: 2

                                // One line each, elided: the card has a fixed height.
                                StyledText {
                                    width: parent.width
                                    text: (modelData.name || modelData.session) + "  ·  " + modelData.kind
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Medium
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    width: parent.width
                                    // Risks the item matched are shown, since an allow acknowledges them.
                                    text: (modelData.risk?.length ? "⚠ " + modelData.risk.join(", ") + " · " : "") + (modelData.summary ?? "")
                                    color: modelData.risk?.length ? Theme.error : Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.spacingS
                                y: (root.cardHeight - 28) / 2
                                IconButton {
                                    icon: "snooze"
                                    onClicked: root.asPerson("mark-attention", { id: modelData.id, action: "snooze", until: Date.now() + 3600000 })
                                }
                                IconButton {
                                    icon: "close"
                                    onClicked: root.asPerson("dismiss-attention", { id: modelData.id })
                                }
                            }

                            Row {
                                x: Theme.spacingM + 3
                                y: root.cardHeight - Theme.spacingXS
                                spacing: Theme.spacingXS
                                visible: card.acts.length > 0

                                Repeater {
                                    model: card.acts

                                    StyledRect {
                                        width: label.implicitWidth + Theme.spacingM * 2
                                        height: 26
                                        radius: 13
                                        color: actArea.containsMouse ? Theme.primary : Theme.surfaceContainerHighest

                                        StyledText {
                                            id: label
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            color: actArea.containsMouse ? Theme.primaryText : Theme.surfaceText
                                            font.pixelSize: Theme.fontSizeSmall
                                        }
                                        MouseArea {
                                            id: actArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.asPerson(modelData.verb, modelData.params)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    SectionLabel {
                        text: "Agents · " + (root.agents.length > 0 ? root.agents.length + (root.working > 0 ? ", " + root.working + " working" : "") : "none running")
                        topPadding: Theme.spacingS
                    }

                    Repeater {
                        model: root.agents

                        StyledRect {
                            width: content.width
                            height: root.agentRowHeight(modelData)
                            radius: Theme.cornerRadius
                            color: agentArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                            MouseArea {
                                id: agentArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.jump({ window: modelData.window_id, session: modelData.session })
                                // The recap shows only while a row is hovered.
                                onContainsMouseChanged: {
                                    if (containsMouse) {
                                        root.recapFor = modelData;
                                        recapDelay.restart();
                                    } else if (root.recapFor?.window_id === modelData.window_id) {
                                        root.recapFor = null;
                                        root.recapText = "";
                                    }
                                }
                            }

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                x: Theme.spacingM
                                y: (root.agentHeight - height) / 2
                                color: root.agentColor(modelData)
                            }

                            Column {
                                x: Theme.spacingM + 16
                                y: (root.agentHeight - 32) / 2
                                width: parent.width - x - Theme.spacingM
                                spacing: 1

                                StyledText {
                                    width: parent.width
                                    // done with subagents at work reads as their work, as tuios's rail does.
                                    text: modelData.name + "  ·  " + (modelData.state === "done" && modelData.subagents > 0 ? "subagents running" : modelData.state) + (modelData.meta?.cost ? "  ·  " + modelData.meta.cost : "") + (modelData.meta?.context ? "  ·  ctx " + modelData.meta.context : "")
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    width: parent.width
                                    text: modelData.message || modelData.cwd || ""
                                    color: Theme.surfaceVariantText
                                    font.pixelSize: Theme.fontSizeSmall
                                    wrapMode: Text.NoWrap
                                    elide: Text.ElideRight
                                    visible: text !== ""
                                }

                                // One line per subagent, as tuios's rail draws them; an
                                // ended one stays listed for a minute.
                                Repeater {
                                    model: modelData.subagent_list ?? []

                                    StyledText {
                                        width: parent.width
                                        height: root.subagentHeight
                                        text: "↳ " + (modelData.description || modelData.type) + "  ·  " + (modelData.state === "running" ? (modelData.now || modelData.last || "running") : modelData.state) + "  ·  " + modelData.tools + " tools"
                                        color: modelData.state === "running" ? Theme.primary : modelData.state === "failed" ? Theme.error : Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                        wrapMode: Text.NoWrap
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    SectionLabel {
                        text: "Recap · last hour"
                        visible: root.recapText !== ""
                        topPadding: Theme.spacingS
                    }

                    StyledRect {
                        width: content.width
                        height: 104
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        visible: root.recapText !== ""

                        StyledText {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            text: (root.recapFor?.name ?? "") + ": " + root.recapText
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            maximumLineCount: 5
                        }
                    }

                    SectionLabel {
                        text: "New agent"
                        visible: root.agentCommand !== ""
                        topPadding: Theme.spacingS
                    }

                    StyledRect {
                        width: content.width
                        height: 40
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh
                        border.color: newAgent.activeFocus ? Theme.primary : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.1)
                        border.width: 1
                        visible: root.agentCommand !== ""

                        TextInput {
                            id: newAgent
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeSmall
                            clip: true
                            // Enter starts the harness in a new pane with this task.
                            onAccepted: if (text.trim() !== "") {
                                startProcess.command = [root.tuios, "start-agent", root.agentCommand, "--prompt", text.trim()];
                                startProcess.running = true;
                                text = "";
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Type a task, Enter to start"
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                visible: newAgent.text === "" && !newAgent.activeFocus
                            }
                        }
                    }
                }
            }
        }
    }
}
