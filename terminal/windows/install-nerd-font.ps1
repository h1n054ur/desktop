# Installs CaskaydiaCove Nerd Font per-user (no admin) and sets it as the Windows Terminal font.
# Run in PowerShell:  powershell -ExecutionPolicy Bypass -File .\install-nerd-font.ps1
$ErrorActionPreference = 'Stop'
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
$reg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$tmp = Join-Path $env:TEMP 'nerdfont'
New-Item -ItemType Directory -Force -Path $fontDir, $tmp | Out-Null

Write-Host '==> downloading CascadiaCode Nerd Font'
$tag = (Invoke-RestMethod 'https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest').tag_name
Invoke-WebRequest "https://github.com/ryanoasis/nerd-fonts/releases/download/$tag/CascadiaCode.zip" -OutFile "$tmp\CascadiaCode.zip"
Expand-Archive "$tmp\CascadiaCode.zip" -DestinationPath $tmp -Force

Add-Type -AssemblyName System.Drawing
Add-Type -Name Gdi -Namespace W -MemberDefinition '[DllImport("gdi32.dll")] public static extern int AddFontResource(string p); [DllImport("user32.dll")] public static extern int SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);'
Write-Host '==> installing (per-user)'
Get-ChildItem "$tmp\CaskaydiaCoveNerdFont*-Regular.ttf", "$tmp\CaskaydiaCoveNerdFont*-Bold.ttf", "$tmp\CaskaydiaCoveNerdFont*-Italic.ttf", "$tmp\CaskaydiaCoveNerdFont*-BoldItalic.ttf" |
  Where-Object { $_.BaseName -notmatch 'Propo' } | ForEach-Object {
    $dst = Join-Path $fontDir $_.Name
    if (-not (Test-Path $dst)) { Copy-Item $_.FullName $dst }
    $pfc = New-Object System.Drawing.Text.PrivateFontCollection
    $pfc.AddFontFile($dst)
    $style = ($_.BaseName -split '-')[1] -replace 'BoldItalic', 'Bold Italic'
    $name = "$($pfc.Families[0].Name) $style (TrueType)"
    New-ItemProperty -Path $reg -Name $name -Value $dst -PropertyType String -Force | Out-Null
    [W.Gdi]::AddFontResource($dst) | Out-Null
    Write-Host "    $name"
  }
[W.Gdi]::SendMessage([IntPtr]0xffff, 0x1D, [IntPtr]0, [IntPtr]0) | Out-Null

$wt = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
if (Test-Path $wt) {
  Write-Host '==> setting Windows Terminal default font'
  Copy-Item $wt "$wt.bak" -Force
  $s = Get-Content $wt -Raw
  if ($s -notmatch 'CaskaydiaCove NFM') {
    $s = [regex]::Replace($s, '("defaults"\s*:\s*\{)', "`$1`n            `"font`": { `"face`": `"CaskaydiaCove NFM`", `"size`": 11 },", 1)
    Set-Content $wt $s -Encoding UTF8
  }
}
Remove-Item $tmp -Recurse -Force
Write-Host '==> done. restart Windows Terminal.'
