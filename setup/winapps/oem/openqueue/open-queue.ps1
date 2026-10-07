# WinApps open queue: Linux drops a .txt with a \\tsclient\home\... path into
# \\tsclient\home\.queue when you double-click an Office file; this opens it here.
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\WinAppsOpenQueue', [ref]$created)
if (-not $created) { exit }
$q = '\\tsclient\home\.queue'
while ($true) {
    if (Test-Path -LiteralPath $q) {
        Get-ChildItem -LiteralPath $q -Filter '*.txt' -EA SilentlyContinue | Sort-Object Name | ForEach-Object {
            $p = Get-Content -LiteralPath $_.FullName -Raw -EA SilentlyContinue
            Remove-Item -LiteralPath $_.FullName -Force -EA SilentlyContinue
            if ($p) {
                $p = $p.Trim()
                if ($p -like '\\tsclient\home\*' -and (Test-Path -LiteralPath $p)) { Start-Process -FilePath $p }
            }
        }
    }
    Start-Sleep -Milliseconds 700
}
