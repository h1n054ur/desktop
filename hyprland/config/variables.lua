-- Hyprland default apps

TERMINAL     = "kitty"
FILE_MANAGER = "dolphin"
BROWSER      = "google-chrome-stable"
EDITOR       = "kate"
CALCULATOR   = "gnome-calculator"

-- Screens: set per machine in ../host/<hostname>.lua (matched by serial, not by port)
MAIN_SCREEN = "" -- the left screen: workspaces 1-5, the full bar, the sign-in panel
SIDE_SCREEN = "" -- the right screen: workspaces 6-10, the slim bar; Discord, Windows apps and games open here

-- Workspaces
KITTY_WORKSPACE = "6" -- where the first kitty opens at login (the right screen); host files can change it
NUM_WPM = 5 -- Number of workspaces per monitor (Max 10)
