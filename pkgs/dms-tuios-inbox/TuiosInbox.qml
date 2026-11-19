// tuios's Inbox (what agents wait on you for, in every session) as a dank-bar
// widget: hidden while the Inbox is empty, a count coloured by the most urgent
// item otherwise, and a popout listing the items. Clicking one focuses its pane
// and raises the terminal.
//
// Live without polling: `tuios subscribe --types attention` prints a line per
// Inbox change, and each line re-reads `tuios list-attention --json`. If the
// daemon is not running, subscribe exits and is retried.
//
// Each item has a close button. tuios lets only the person close an item, so the
// widget holds the person's presence (`attach-presence`, made for programs
// outside every pane) on its own socket connection and sends `dismiss-attention`
// with that nonce, only on a click. Answering prompts stays in tuios.
// pluginData.tuios is the tuios binary, set by modules/nixos/desktop/tuios.nix.
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
    property var items: []

    // The agent is blocked on these; errored is worse, the rest can wait.
    // Colours are the look's roles: accent (Theme.primary) for "needs you".
    readonly property var blocking: ["approval", "plan", "question", "ask"]
    function kindColor(kind) {
        if (kind === "errored")
            return Theme.error;
        if (blocking.includes(kind))
            return Theme.primary;
        return Theme.surfaceVariantText;
    }
    readonly property color statusColor: items.some(i => i.kind === "errored") ? Theme.error : items.some(i => blocking.includes(i.kind)) ? Theme.primary : Theme.surfaceVariantText

    onItemsChanged: setVisibilityOverride(items.length > 0)
    Component.onCompleted: setVisibilityOverride(false)

    // A change during a read re-reads once it ends, so none is missed.
    property bool stale: false
    function refresh() {
        if (listProcess.running)
            stale = true;
        else
            listProcess.running = true;
    }

    function jump(item) {
        // Focus the pane (switching workspace); if a pane is zoomed it would
        // hide the target, so zoom the target instead. Unzoomed layouts stay.
        // shortcut: matches a zoomed pane on any workspace; upgrade to a
        // per-workspace check if that ever zooms a jump that didn't need it.
        Quickshell.execDetached(["sh", "-c", 't="$3"; "$t" focus-window "$1" -s "$2" && if "$t" list-windows -s "$2" --json | grep -q \'"zoomed": true\'; then "$t" zoom-window -w "$1" -s "$2" --on; fi', "jump", item.window, item.session, tuios]);
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
        command: [root.tuios, "list-attention", "--json"]
        stdout: StdioCollector {
            id: listOutput
        }
        onExited: {
            try {
                root.items = JSON.parse(listOutput.text).items ?? [];
            } catch (e) {
                root.items = [];
            }
            if (root.stale) {
                root.stale = false;
                running = true;
            }
        }
    }

    Process {
        id: subscribeProcess
        command: [root.tuios, "subscribe", "--types", "attention"]
        running: true
        stdout: SplitParser {
            onRead: root.refresh()
        }
        onExited: retry.start()
    }

    Timer {
        id: retry
        interval: 5000
        onTriggered: subscribeProcess.running = true
    }

    // The person's presence: connected on the first close, kept open (the nonce
    // lives as long as the connection), and re-made after the daemon restarts.
    property string nonce: ""
    property var pendingDismiss: []
    property int requestId: 1
    function send(verb, params) {
        presence.write(JSON.stringify({ id: ++requestId, verb: verb, params: params }) + "\n");
        presence.flush();
        return requestId;
    }
    function dismiss(item) {
        if (nonce !== "") {
            send("dismiss-attention", { id: item.id, human_nonce: nonce });
            return;
        }
        pendingDismiss.push(item.id);
        if (!presence.connected)
            presence.connected = true;
    }
    property int presenceRequest: 0
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
                if (r.id !== root.presenceRequest)
                    return;
                // Reply envelope not documented; take the nonce wherever it sits.
                root.nonce = r.result?.human_nonce ?? r.data?.human_nonce ?? r.human_nonce ?? "";
                if (root.nonce === "") {
                    console.warn("tuiosInbox: attach-presence refused: " + line);
                    root.pendingDismiss = [];
                    return;
                }
                for (const id of root.pendingDismiss)
                    root.send("dismiss-attention", { id: id, human_nonce: root.nonce });
                root.pendingDismiss = [];
            }
        }
    }

    popoutWidth: 440
    // Header plus one fixed-height card per item (rowHeight), capped.
    readonly property int rowHeight: 56
    popoutHeight: Math.min(560, 110 + items.length * (rowHeight + Theme.spacingXS))

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
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
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            DIcon {
                name: "inbox"
                size: root.iconSize
                color: root.statusColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.items.length
                color: root.statusColor
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            width: parent ? parent.width : 0
            headerText: "TUIOS Inbox"
            detailsText: root.items.length + " waiting"
            showCloseButton: false

            Column {
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: root.items

                    // The card style of the itera update widget.
                    StyledRect {
                        width: parent.width
                        height: root.rowHeight
                        radius: Theme.cornerRadius
                        color: rowArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.1)
                        border.width: 1

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
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingM + 3
                            anchors.rightMargin: Theme.spacingM + 28
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
                                text: modelData.summary ?? ""
                                color: Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.jump(modelData)
                        }

                        // After rowArea, so it takes its own clicks.
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 14
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            color: closeArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                            DIcon {
                                anchors.centerIn: parent
                                name: "close"
                                size: Theme.iconSizeSmall
                                color: closeArea.containsMouse ? Theme.surfaceText : Theme.surfaceVariantText
                            }

                            MouseArea {
                                id: closeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.dismiss(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
