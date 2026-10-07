#!/usr/bin/env bash
# Started by hyprland.lua inside the greeter's Hyprland. Runs the Quickshell greeter, records how it
# ended, then closes Hyprland. launch.sh reads the status: 0 means you signed in (Quickshell exits after
# handing the session to greetd); anything else means the greeter failed and Noctalia Greeter takes over.
STATUS=/var/cache/h1n054ur-greeter/qs-status
quickshell -p /etc/greetd/h1n054ur/shell.qml 2>&1 | systemd-cat -t h1n054ur-greeter-qs -p info
echo "${PIPESTATUS[0]}" > "$STATUS"
hyprctl dispatch exit
