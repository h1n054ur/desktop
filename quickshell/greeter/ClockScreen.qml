// Other screens: the time and date, centred, over the dimmed wallpaper
import QtQuick
import QtQuick.Window

Item {
    id: side
    required property var shell
    required property var clock

    Image {
        anchors.fill: parent
        source: "file://" + side.shell.assets + "/right.png"
        fillMode: Image.Stretch
        asynchronous: true
    }
    Rectangle { anchors.fill: parent; color: Theme.bg; opacity: 0.7 }

    // On the lock screen the compositor gives the keyboard to whichever screen is focused; when that is a
    // clock screen, pass every key to the sign-in panel so typing works without clicking the left screen first
    Item {
        id: keys
        focus: true
        readonly property bool windowActive: Window.active
        Component.onCompleted: forceActiveFocus()
        onWindowActiveChanged: if (windowActive) forceActiveFocus()
        Keys.onPressed: event => { side.shell.forwardedKey(event.key, event.text); event.accepted = true; }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -10
        spacing: 0
        GradientText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(side.clock.date, "HH:mm")
            font.family: Theme.mono
            font.pixelSize: 220
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(side.clock.date, "dddd, d MMMM").toLowerCase()
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 30
            font.letterSpacing: 1
        }
    }
}
