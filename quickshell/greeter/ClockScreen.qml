// Other screens: the time and date, centred, over the dimmed wallpaper
import QtQuick

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
