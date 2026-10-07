// h1n054ur session shell: the lock screen and the session menu, in the same look as the login screen.
//   qs -c h1n054ur ipc call lock lock
//   qs -c h1n054ur ipc call session toggle
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    Lock { id: lock }
    SessionMenu { id: menu; onLockRequested: lock.lock() }

    IpcHandler {
        target: "lock"
        function lock(): void { lock.lock(); }
        function isLocked(): bool { return lock.locked; }
    }
    IpcHandler {
        target: "session"
        function toggle(): void { menu.toggle(); }
        function open(): void { menu.open(); }
        function close(): void { menu.close(); }
    }
}
