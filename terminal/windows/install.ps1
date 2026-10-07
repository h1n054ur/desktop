# Installs the h1n054ur terminal on Windows: PowerShell 7, starship, fastfetch, TerminalTextEffects,
# the Nerd Font, and sets PowerShell 7 with that font as the Windows Terminal default.
# Run in PowerShell:  powershell -ExecutionPolicy Bypass -File .\windows\install.ps1 [-Handle yourhandle]
param([string]$Handle = $env:USERNAME)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here
function Say($m) { Write-Host "==> $m" -ForegroundColor Green }

Say 'winget: PowerShell 7, starship, fastfetch, python'
foreach ($id in 'Microsoft.PowerShell', 'Starship.Starship', 'Fastfetch-cli.Fastfetch', 'Python.Python.3.13') {
  winget install --id $id -e --accept-source-agreements --accept-package-agreements --silent | Out-Null
}
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')

Say 'terminaltexteffects + pyfiglet (pip --user)'
py -3 -m pip install --user --quiet --upgrade terminaltexteffects pyfiglet
$scripts = & py -3 -c "import sysconfig;print(sysconfig.get_path('scripts','nt_user'))"
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$scripts*") {
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$scripts", 'User')
  $env:Path += ";$scripts"
}

Say 'configs'
$cfg = Join-Path $HOME '.config'
New-Item -ItemType Directory -Force -Path "$cfg\welcome", "$cfg\fastfetch", "$HOME\.local\bin" | Out-Null
Copy-Item "$here\welcome.ps1" "$HOME\.local\bin\welcome.ps1" -Force
Copy-Item "$here\fastfetch\welcome.jsonc" "$cfg\fastfetch\welcome.jsonc" -Force
if (Test-Path "$cfg\starship.toml") { Copy-Item "$cfg\starship.toml" "$cfg\starship.toml.bak" -Force }
Copy-Item "$repo\config\starship.toml" "$cfg\starship.toml" -Force
Set-Content "$cfg\welcome\handle" $Handle -NoNewline
& py -3 -c "import pyfiglet,sys;open(sys.argv[2],'w',encoding='utf-8').write(pyfiglet.figlet_format(sys.argv[1],font='ansi_shadow').rstrip()+'\n')" $Handle "$cfg\welcome\banner.txt"

Say 'PowerShell 7 profile hook'
$profile7 = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
New-Item -ItemType Directory -Force -Path (Split-Path $profile7) | Out-Null
if (-not (Test-Path $profile7) -or -not (Select-String -Path $profile7 -Pattern '>>> h1n054ur-terminal >>>' -Quiet)) {
  Add-Content $profile7 ("`n" + (Get-Content "$here\profile.ps1" -Raw)) -Encoding UTF8
}

Say 'Nerd Font + Windows Terminal font'
& "$here\install-nerd-font.ps1"

Say 'Windows Terminal: PowerShell 7 as default profile, Windows PowerShell hidden'
$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wt) {
  $s = Get-Content $wt -Raw
  $s = [regex]::Replace($s, '"defaultProfile"\s*:\s*"\{[0-9a-f-]+\}"', '"defaultProfile": "{574e775e-4f2a-5b96-ac1e-a2962a402336}"', 1)
  # hide the Windows PowerShell 5.1 profile
  $s = [regex]::Replace($s, '("guid"\s*:\s*"\{61c54bbd-c2c6-5271-96e7-009a87ff44bf\}")(?![^}]*"hidden")', '$1, "hidden": true', 1)
  Set-Content $wt $s -Encoding UTF8
}
Say 'done. restart Windows Terminal and open a PowerShell tab, or run: welcome'
