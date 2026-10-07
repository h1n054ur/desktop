# >>> h1n054ur-terminal >>>
[Console]::OutputEncoding = [Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-Alias welcome "$HOME\.local\bin\welcome.ps1"
if (-not $env:WELCOME_SHOWN -and -not $env:WELCOME_OFF -and $Host.UI.RawUI.WindowSize.Width -ge 70) {
  $env:WELCOME_SHOWN = 1
  welcome
}
Invoke-Expression (& starship init powershell)
# <<< h1n054ur-terminal <<<
