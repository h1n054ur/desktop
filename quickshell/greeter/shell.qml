// h1n054ur greeter for greetd (Quickshell). The left-most screen signs in, every other screen shows the clock.
// Without a greetd socket it runs a pretend login, so it can be previewed inside a normal session.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Greetd
import Quickshell.Io

ShellRoot {
    id: root

    // What to sign in as and what to start; overridable with environment variables for other machines
    // who signs in: launch.sh exports it from the "user" file install.sh writes (the account that ran sudo)
    readonly property string user: Quickshell.env("H1N_GREETER_USER") || Quickshell.env("USER") || "user"
    readonly property var session: ["uwsm", "start", "-e", "-D", "Hyprland", "hyprland.desktop"]
    readonly property string sessionName: "Hyprland (uwsm)"
    readonly property string assets: Quickshell.env("H1N_GREETER_ASSETS") || Qt.resolvedUrl("assets").toString().replace("file://", "")
    readonly property string banner: "██╗  ██╗ ██╗███╗   ██╗ ██████╗ ███████╗██╗  ██╗██╗   ██╗██████╗ \n██║  ██║███║████╗  ██║██╔═████╗██╔════╝██║  ██║██║   ██║██╔══██╗\n███████║╚██║██╔██╗ ██║██║██╔██║███████╗███████║██║   ██║██████╔╝\n██╔══██║ ██║██║╚██╗██║████╔╝██║╚════██║╚════██║██║   ██║██╔══██╗\n██║  ██║ ██║██║ ╚████║╚██████╔╝███████║     ██║╚██████╔╝██║  ██║\n╚═╝  ╚═╝ ╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝\n                                                                \n"
    readonly property bool preview: !Greetd.available
    readonly property int leftX: {
        let x = Infinity;
        for (let i = 0; i < Quickshell.screens.length; i++) x = Math.min(x, Quickshell.screens[i].x);
        return x;
    }

    // shown in the panel header; read from /etc/hostname
    readonly property string host: hostFile.text().trim() || "localhost"
    FileView { id: hostFile; path: "/etc/hostname"; blockLoading: true }

    property string status: ""
    property bool busy: false
    // shared with the lock screen, which sets its own wording
    readonly property string hint: "enter to sign in"
    readonly property string busyHint: "signing in..."

    function start() {
        status = "";
        if (!preview) Greetd.createSession(user);
    }
    function submit(text) {
        if (busy) return;
        busy = true;
        if (preview) {
            status = text === "demo" ? "signed in (preview)" : "wrong password";
            busy = false;
            if (text === "demo") Qt.quit();
            return;
        }
        Greetd.respond(text);
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            root.busy = false;
            if (error) root.status = message;
        }
        function onAuthFailure(message) {
            root.busy = false;
            root.status = "wrong password";
            // the failed session has already ended (Quickshell docs), so just start a fresh one
            Greetd.createSession(root.user);
        }
        function onReadyToLaunch() { Greetd.launch(root.session); }
        function onError(error) { root.busy = false; root.status = error; }
    }

    Component.onCompleted: start()

    // Safety net for the in-session preview: never hold the screens for more than two minutes
    Timer { running: root.preview; interval: 120000; onTriggered: Qt.quit() }

    SystemClock { id: sysClock; precision: SystemClock.Minutes }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property bool isLogin: modelData.x === root.leftX
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "h1n054ur-greeter"
            WlrLayershell.keyboardFocus: isLogin ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "#06090a"

            Loader {
                anchors.fill: parent
                sourceComponent: win.isLogin ? loginScreen : clockScreen
            }
        }
    }

    Component {
        id: loginScreen
        LoginScreen {
            shell: root
            clock: sysClock
        }
    }
    Component {
        id: clockScreen
        ClockScreen {
            shell: root
            clock: sysClock
        }
    }
}
