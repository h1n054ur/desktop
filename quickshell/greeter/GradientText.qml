// Text filled with the h1n054ur green-to-cyan gradient
import QtQuick
import QtQuick.Effects

Item {
    id: g
    property alias text: label.text
    property alias font: label.font
    property alias lineHeight: label.lineHeight
    property color glow: "transparent"
    property real glowBlur: 0.6
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    Text {
        id: label
        visible: false
        color: "white"
        textFormat: Text.PlainText
        lineHeightMode: Text.ProportionalHeight
    }
    Rectangle {
        id: fill
        anchors.fill: label
        visible: false
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.green }
            GradientStop { position: 1; color: Theme.cyan }
        }
    }
    // Letters filled with the gradient; an optional soft glow is drawn from the finished letters
    Item {
        anchors.fill: label
        layer.enabled: g.glow.a > 0
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: g.glow
            shadowBlur: g.glowBlur
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            autoPaddingEnabled: true
        }
        MultiEffect {
            anchors.fill: parent
            source: fill
            maskEnabled: true
            maskSource: ShaderEffectSource { sourceItem: label; hideSource: true }
        }
    }
}
