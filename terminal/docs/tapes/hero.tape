Output docs/hero.gif
Set Shell bash
Set FontFamily "CaskaydiaCove NFM"
Set FontSize 16
Set Width 1000
Set Height 660
Set Padding 16
Set Framerate 30
Set WindowBar Colorful
Set Theme "Dracula"
Env WELCOME_DEMO "1"
Hide
Type `eval "$(starship init bash)"; cd ~/desktop/terminal; clear` Enter
Type "welcome matrix" Enter
Show
Sleep 5.5s
Type "git log --oneline -3" Sleep 400ms Enter
Sleep 1.5s
Type "ls" Sleep 300ms Enter
Sleep 1.2s
Type "welcome --list | tr '\n' ' '" Sleep 300ms Enter
Sleep 1.5s
Type "false" Sleep 300ms Enter
Sleep 1.5s
Type "sleep 2" Sleep 300ms Enter
Sleep 4s
