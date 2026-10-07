# terminal welcome screen, PowerShell port (github.com/h1n054ur/h1n054ur-terminal)
#   welcome            random effect
#   welcome <effect>   force one effect
#   welcome -List      show effects
param([string]$Effect, [switch]$List)

$cfg     = Join-Path $HOME '.config'
$banner  = Join-Path $cfg 'welcome\banner.txt'
$ffCfg   = Join-Path $cfg 'fastfetch\welcome.jsonc'
$hfile   = Join-Path $cfg 'welcome\handle'
$handle  = if (Test-Path $hfile) { (Get-Content $hfile -Raw).Trim() } else { $env:USERNAME }
$e = [char]27
$G = "$e[1;32m"; $C = "$e[1;36m"; $W = "$e[1;37m"; $D = "$e[2;37m"; $R = "$e[0m"

$grad = '39ff14', '00e5ff'
$fin  = @('--final-gradient-stops') + $grad + @('--final-gradient-direction', 'horizontal')
$effects = [ordered]@{
  matrix    = @{ fps = 90;  args = @('matrix', '--rain-time', '2') + $fin }
  rain      = @{ fps = 75;  args = @('rain') + $fin }
  decrypt   = @{ fps = 200; args = @('decrypt', '--typing-speed', '10') + $fin }
  beams     = @{ fps = 100; args = @('beams') + $fin }
  burn      = @{ fps = 120; args = @('burn') + $fin }
  unstable  = @{ fps = 75;  args = @('unstable') + $fin }
  synthgrid = @{ fps = 60;  args = @('synthgrid', '--text-gradient-stops') + $grad + @('--text-gradient-direction', 'horizontal') }
  slide     = @{ fps = 60;  args = @('slide') + $fin }
  vhstape   = @{ fps = 180; args = @('vhstape') + $fin }
  laseretch = @{ fps = 240; args = @('laseretch') + $fin }
}

if ($List) { $effects.Keys | Sort-Object; return }
if ($Effect -and -not $effects.Contains($Effect)) { Write-Error "unknown effect: $Effect (see welcome -List)"; return }
$pick = if ($Effect) { $Effect } else { $effects.Keys | Get-Random }

function Show-StaticBanner {
  foreach ($line in Get-Content $banner -Encoding UTF8) {
    $out = ''
    $n = [math]::Max(1, $line.Length - 1)
    for ($i = 0; $i -lt $line.Length; $i++) {
      $t = $i / $n
      $r = [int](0x39 * (1 - $t)); $g = [int](0xff * (1 - $t) + 0xe5 * $t); $b = [int](0x14 * (1 - $t) + 0xff * $t)
      $out += "$e[38;2;$r;$g;${b}m" + $line[$i]
    }
    Write-Host "$out$R"
  }
}

Clear-Host
function Set-Cursor($on) { try { [Console]::CursorVisible = $on } catch {} }
Set-Cursor $false
try {
  & tte -i $banner --frame-rate $effects[$pick].fps @($effects[$pick].args) 2>$null
  if ($LASTEXITCODE -ne 0) { Clear-Host; Show-StaticBanner }
} catch {
  Clear-Host; Show-StaticBanner
} finally {
  Set-Cursor $true
}

Write-Host
& fastfetch --config $ffCfg

$tips = @(
  'the quieter you become, the more you are able to hear'
  'talk is cheap. show me the code'
  'there is no patch for human stupidity'
  'rm -rf fear/'
  'every system has a backdoor. it is usually a human'
  'ship it, then harden it'
  'security through obscurity is not security'
  'sudo make me a sandwich'
  'if it works, you have not tested it enough'
  'logs or it did not happen'
)
$tip = $tips | Get-Random
Write-Host "`n ${G}[ ACCESS GRANTED ]${R} ${W}${handle}${D}@${W}$($env:COMPUTERNAME.ToLower())${R}  ${D}▸${R}  ${C}effect:${R} $pick  ${D}▸${R}  ${D}${tip}${R}`n"
