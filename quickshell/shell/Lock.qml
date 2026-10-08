// Lock screen: the login screen's design on every screen (sign-in panel on the left-most screen,
// centred clock on the others), unlocked with your password through PAM (the "hyprlock" service).
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Io
import "greeter"

Scope {
    id: lockRoot
    property alias locked: sessionLock.locked

    // the object LoginScreen and ClockScreen read from, same shape as the greeter's root
    QtObject {
        id: lockState
        readonly property string user: Quickshell.env("USER") || "user"
        readonly property string host: lockHost.text().trim() || "localhost"
        readonly property string sessionName: "locked"
        readonly property string assets: Qt.resolvedUrl("greeter/assets").toString().replace("file://", "")
        readonly property bool preview: false
        readonly property string hint: "enter to unlock"
        readonly property string busyHint: "checking..."
        readonly property bool showPower: false
        property string status: ""
        property bool busy: false
        property string pending: ""
        // a key typed on a clock screen, for the sign-in panel (LoginScreen) to apply
        signal forwardedKey(int key, string text)

        function submit(text) {
            if (busy) return;
            busy = true;
            status = "";
            if (pam.responseRequired) {
                pam.respond(text);
            } else {
                pending = text;
                if (!pam.active) pam.start();
            }
        }
    }

    function lock() {
        lockState.status = "";
        lockState.busy = false;
        sessionLock.locked = true;
    }

    FileView { id: lockHost; path: "/etc/hostname"; blockLoading: true }

    PamContext {
        id: pam
        // nested tests set H1N_LOCK_PAM_DIR to a folder with allow/deny files; real use is /etc/pam.d/hyprlock
        configDirectory: Quickshell.env("H1N_LOCK_PAM_DIR") || "/etc/pam.d"
        config: Quickshell.env("H1N_LOCK_PAM") || "hyprlock"
        onPamMessage: {
            if (responseRequired && lockState.pending !== "") {
                const t = lockState.pending;
                lockState.pending = "";
                respond(t);
            } else if (messageIsError) {
                lockState.status = message;
            }
        }
        onCompleted: result => {
            console.log("h1n-lock: pam result=" + result + " success=" + (result === PamResult.Success));
            lockState.busy = false;
            if (result === PamResult.Success) {
                sessionLock.locked = false;
                lockState.status = "";
            } else {
                // wait for the next try instead of restarting at once (submit() starts a new check)
                lockState.status = "wrong password";
            }
        }
        onError: error => { lockState.busy = false; lockState.status = "auth error"; }
    }

    SystemClock { id: sysClock; precision: SystemClock.Minutes }

    // Test hooks for tests/nested.sh only (never set in real use):
    //   H1N_LOCK_AUTOLOCK=1     lock as soon as the shell starts
    //   H1N_LOCK_AUTOTYPE=text  submit this as the password 1.5 s after locking
    Component.onCompleted: if (Quickshell.env("H1N_LOCK_AUTOLOCK") === "1") lockRoot.lock()
    Timer {
        running: sessionLock.locked && (Quickshell.env("H1N_LOCK_AUTOTYPE") || "") !== ""
        interval: 1500
        onTriggered: lockState.submit(Quickshell.env("H1N_LOCK_AUTOTYPE"))
    }


    readonly property int leftX: {
        let x = Infinity;
        for (let i = 0; i < Quickshell.screens.length; i++) x = Math.min(x, Quickshell.screens[i].x);
        return x;
    }

    WlSessionLock {
        id: sessionLock
        onLockedChanged: {
            console.log("h1n-lock: locked=" + locked);
            if (locked && !pam.active) pam.start();
        }

        WlSessionLockSurface {
            id: surface
            color: Theme.bg
            readonly property bool isLogin: surface.screen && surface.screen.x === lockRoot.leftX
            Loader {
                anchors.fill: parent
                focus: true
                sourceComponent: surface.isLogin ? loginComp : clockComp
            }
            Component { id: loginComp; LoginScreen { shell: lockState; clock: sysClock } }
            Component { id: clockComp; ClockScreen { shell: lockState; clock: sysClock } }
        }
    }
}
