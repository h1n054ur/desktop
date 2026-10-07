// Session menu (Super+Alt+C, the bar's power icon): a terminal-style panel like the login screen.
// 1-5 or arrows + Enter pick an action; sleep, restart and shutdown count down 3 s (Esc cancels).
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "greeter"

Scope {
    id: menu
    signal lockRequested()
    property bool shown: false
    property int selected: 0
    property int countdown: 0
    property var pendingAction: null
    readonly property string assets: Qt.resolvedUrl("greeter/assets").toString().replace("file://", "")

    readonly property var actions: [
        { key: "1", label: "lock", icon: "lock", hint: "Super+L", confirm: false },
        { key: "2", label: "logout", icon: "logout", hint: "end the session", confirm: false },
        { key: "3", label: "sleep", icon: "moon", hint: "lock, then suspend", confirm: true },
        { key: "4", label: "restart", icon: "restart", hint: "reboot", confirm: true },
        { key: "5", label: "shut down", icon: "power", hint: "power off", confirm: true }
    ]

    function open() { selected = 0; countdown = 0; pendingAction = null; shown = true; }
    function close() { shown = false; countdown = 0; pendingAction = null; tick.stop(); }
    function toggle() { shown ? close() : open(); }

    function run(a) {
        if (a.label === "lock") { close(); menu.lockRequested(); return; }
        if (a.label === "logout") { close(); Quickshell.execDetached(["uwsm", "stop"]); return; }
        if (a.label === "sleep") { close(); menu.lockRequested(); Quickshell.execDetached(["sh", "-c", "sleep 1; systemctl suspend"]); return; }
        if (a.label === "restart") { close(); Quickshell.execDetached(["systemctl", "reboot"]); return; }
        if (a.label === "shut down") { close(); Quickshell.execDetached(["systemctl", "poweroff"]); return; }
    }
    function pick(i) {
        selected = i;
        const a = actions[i];
        if (!a.confirm) { run(a); return; }
        pendingAction = a; countdown = 3; tick.restart();
    }

    Timer {
        id: tick
        interval: 1000; repeat: true
        onTriggered: {
            menu.countdown -= 1;
            if (menu.countdown <= 0) { stop(); if (menu.pendingAction) menu.run(menu.pendingAction); }
        }
    }

    // the screen with keyboard focus gets the panel; every screen gets the dim backdrop
    readonly property string focusedName: Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            visible: menu.shown
            readonly property bool hasPanel: modelData.name === menu.focusedName || (menu.focusedName === "" && modelData.x === 0)
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h1n054ur-session"
            WlrLayershell.keyboardFocus: hasPanel && menu.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: Qt.rgba(6 / 255, 9 / 255, 10 / 255, 0.55)

            MouseArea { anchors.fill: parent; onClicked: menu.close() }

            Rectangle {
                id: panel
                visible: win.hasPanel
                anchors.centerIn: parent
                width: 520
                height: 40 + 12 + list.implicitHeight + 12 + 44
                radius: 12
                color: Qt.rgba(6 / 255, 9 / 255, 10 / 255, 0.96)
                border.color: Theme.line
                border.width: 1
                MouseArea { anchors.fill: parent }   // clicks on the panel do not close it

                Item {
                    id: header
                    width: parent.width; height: 40
                    Text { x: 20; anchors.verticalCenter: parent.verticalCenter; text: (menuHost.text().trim() || "localhost") + "  ·  session"; color: Theme.mute; font.family: Theme.mono; font.pixelSize: 12 }
                    Text {
                        anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "ddd dd MMM HH:mm").toLowerCase()
                        color: Theme.mute; font.family: Theme.mono; font.pixelSize: 12
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
                }

                Column {
                    id: list
                    anchors.top: header.bottom; anchors.topMargin: 12
                    x: 12; width: parent.width - 24
                    spacing: 6
                    Repeater {
                        model: menu.actions
                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool active: menu.selected === index
                            width: list.width; height: 42; radius: 6
                            color: active ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                            border.color: active ? (modelData.label === "shut down" ? Theme.err : Theme.green) : "transparent"
                            border.width: 1.5
                            Row {
                                x: 14; anchors.verticalCenter: parent.verticalCenter; spacing: 14
                                Text { text: modelData.key; color: Theme.label; font.family: Theme.mono; font.pixelSize: 14; anchors.verticalCenter: parent.verticalCenter }
                                Image {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 18; height: 18; sourceSize: Qt.size(36, 36)
                                    source: "file://" + menu.assets + "/" + modelData.icon + "-" + (parent.parent.active ? "39ff14" : "7d8f8a") + ".svg"
                                }
                                Text {
                                    text: modelData.label; anchors.verticalCenter: parent.verticalCenter
                                    color: parent.parent.active ? "white" : Theme.dim; font.family: Theme.mono; font.pixelSize: 14
                                    font.bold: parent.parent.active
                                }
                            }
                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.hint; color: Theme.mute; font.family: Theme.mono; font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onEntered: if (menu.countdown === 0) menu.selected = index
                                onClicked: menu.pick(index)
                            }
                        }
                    }
                }

                Item {
                    anchors.bottom: parent.bottom; width: parent.width; height: 44
                    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.line }
                    Text {
                        x: 20; anchors.verticalCenter: parent.verticalCenter
                        text: menu.countdown > 0 ? (menu.pendingAction.label + " in " + menu.countdown + "s  ·  esc to cancel")
                                                 : "1-5 or ↑↓ enter  ·  esc to close"
                        color: menu.countdown > 0 ? (menu.pendingAction.label === "shut down" ? Theme.err : Theme.green) : Theme.mute
                        font.family: Theme.mono; font.pixelSize: 12
                    }
                }

                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) { if (menu.countdown > 0) { tick.stop(); menu.countdown = 0; menu.pendingAction = null; } else menu.close(); }
                    else if (event.key === Qt.Key_Down) { if (menu.countdown === 0) menu.selected = (menu.selected + 1) % menu.actions.length; }
                    else if (event.key === Qt.Key_Up) { if (menu.countdown === 0) menu.selected = (menu.selected + menu.actions.length - 1) % menu.actions.length; }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (menu.countdown === 0) menu.pick(menu.selected); }
                    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) { if (menu.countdown === 0) menu.pick(event.key - Qt.Key_1); }
                    event.accepted = true;
                }
                onVisibleChanged: if (visible) forceActiveFocus()
            }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    FileView { id: menuHost; path: "/etc/hostname"; blockLoading: true }
}
