// Left screen: the h1n054ur banner and a terminal-style sign-in panel over the dimmed wallpaper
import QtQuick
import Quickshell

Item {
    id: login
    required property var shell
    required property var clock

    Image {
        anchors.fill: parent
        source: "file://" + login.shell.assets + "/left.png"
        fillMode: Image.Stretch
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; color: Theme.bg; opacity: 0.8 }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -18
        spacing: 16

        // The banner is pre-rendered (assets/banner.png, 24 px glow margin) so its box-drawing strokes match the mockup exactly
        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            source: "file://" + login.shell.assets + "/banner.png"
            width: 880; height: 210
            smooth: false
        }

        Rectangle {
            id: panel
            anchors.horizontalCenter: parent.horizontalCenter
            width: 640
            height: 40 + 24 + body.implicitHeight + 16 + 44
            radius: 12
            color: Qt.rgba(6 / 255, 9 / 255, 10 / 255, 0.9)
            border.color: Theme.line
            border.width: 1

            // header: host and time
            Item {
                id: header
                width: parent.width; height: 40
                Text { x: 20; anchors.verticalCenter: parent.verticalCenter; text: login.shell.host || "localhost"; color: Theme.mute; font.family: Theme.mono; font.pixelSize: 12 }
                Text {
                    anchors.right: parent.right; anchors.rightMargin: 20; anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(login.clock.date, "ddd dd MMM HH:mm").toLowerCase()
                    color: Theme.mute; font.family: Theme.mono; font.pixelSize: 12
                }
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.line }
            }

            Grid {
                id: body
                anchors.top: header.bottom; anchors.topMargin: 24
                x: 24
                columns: 2; columnSpacing: 0; rowSpacing: 12
                verticalItemAlignment: Grid.AlignTop

                Text { width: 120; text: "user"; color: Theme.label; font.family: Theme.mono; font.pixelSize: 14 }
                Text { text: login.shell.user; color: "white"; font.family: Theme.mono; font.pixelSize: 14; font.bold: true }

                Text { width: 120; text: "session"; color: Theme.label; font.family: Theme.mono; font.pixelSize: 14 }
                Text { text: login.shell.sessionName; color: Theme.dim; font.family: Theme.mono; font.pixelSize: 14 }

                Text { width: 120; text: "password"; color: Theme.label; font.family: Theme.mono; font.pixelSize: 14 }
                Rectangle {
                    width: 472; height: 40; radius: 6
                    color: Qt.rgba(1, 1, 1, 0.05)
                    border.color: login.shell.status === "wrong password" ? Theme.err : Theme.green
                    border.width: 1.5
                    Row {
                        x: 12; anchors.verticalCenter: parent.verticalCenter; spacing: 2
                        Text {
                            text: "●".repeat(pw.text.length)
                            color: Theme.fg; font.family: Theme.mono; font.pixelSize: 14; font.letterSpacing: 4
                        }
                        Rectangle {
                            width: 10; height: 20; color: Theme.green
                            SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0; duration: 530 } NumberAnimation { to: 1; duration: 530 } }
                        }
                    }
                    TextInput {
                        id: pw
                        anchors.fill: parent
                        opacity: 0
                        echoMode: TextInput.Password
                        focus: true
                        enabled: !login.shell.busy
                        Keys.onReturnPressed: { const t = text; text = ""; login.shell.submit(t) }
                        Keys.onEnterPressed: { const t = text; text = ""; login.shell.submit(t) }
                        Keys.onEscapePressed: { text = ""; if (login.shell.preview) Qt.quit() }
                        Component.onCompleted: forceActiveFocus()
                    }
                }
            }

            // footer: hint or error, and power actions
            Item {
                anchors.bottom: parent.bottom; width: parent.width; height: 44
                Text {
                    x: 24; anchors.verticalCenter: parent.verticalCenter
                    text: login.shell.status !== "" ? login.shell.status
                        : login.shell.busy ? (login.shell.busyHint || "signing in...") : (login.shell.preview ? "preview: type demo, esc to close" : (login.shell.hint || "enter to sign in"))
                    color: login.shell.status === "wrong password" ? Theme.err : Theme.mute
                    font.family: Theme.mono; font.pixelSize: 12
                }
                Row {
                    // the lock screen hides these (a click on sleep there once suspended a locked session)
                    visible: login.shell.showPower !== false
                    anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter
                    spacing: 20
                    Repeater {
                        model: [ { label: "sleep", icon: "moon", cmd: ["systemctl", "suspend"] },
                                 { label: "restart", icon: "restart", cmd: ["systemctl", "reboot"] },
                                 { label: "off", icon: "power", cmd: ["systemctl", "poweroff"] } ]
                        Row {
                            required property var modelData
                            spacing: 6
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16; sourceSize: Qt.size(32, 32)
                                source: "file://" + login.shell.assets + "/" + modelData.icon + "-" + (hover.hovered ? "39ff14" : "7d8f8a") + ".svg"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: hover.hovered ? Theme.green : Theme.mute
                                font.family: Theme.mono; font.pixelSize: 12
                            }
                            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: if (!login.shell.preview) Quickshell.execDetached(modelData.cmd) }
                        }
                    }
                }
            }
        }
    }
}
