:: h1n054ur additions to WinApps' oem\install.bat: append this file to the end of the upstream script
:: (https://github.com/winapps-org/winapps/blob/main/oem/install.bat) before the first start.

:: Install Microsoft 365 Apps (Word, Excel, PowerPoint, Outlook, ...) with the Office Deployment Tool.
:: Sign in with your Microsoft 365 account on first launch to activate.
echo [INFO] Installing Microsoft 365 Apps...
mkdir C:\ODT >nul 2>&1
copy /Y "%~dp0office.xml" C:\ODT\office.xml >nul
curl.exe -sSL -o C:\ODT\setup.exe https://officecdn.microsoft.com/pr/wsus/setup.exe
if exist C:\ODT\setup.exe (
    C:\ODT\setup.exe /configure C:\ODT\office.xml
    echo [SUCCESS] Microsoft 365 Apps installed.
) else (
    echo [ERROR] Failed to download the Office Deployment Tool.
)

:: Install OneDrive for all users (sign in to your accounts after setup, in the full desktop).
echo [INFO] Installing OneDrive...
curl.exe -sSL -o C:\ODT\OneDriveSetup.exe "https://go.microsoft.com/fwlink/?linkid=844652"
if exist C:\ODT\OneDriveSetup.exe (
    C:\ODT\OneDriveSetup.exe /allusers /silent
    echo [SUCCESS] OneDrive installed.
) else (
    echo [ERROR] Failed to download OneDrive.
)

:: Optional: FileMaker Pro, silently, if you put its installer in oem\filemaker (see oem/filemaker/README.md).
:: Your licence certificate (LicenseCert.fmcert) goes next to Setup.exe; never commit it.
echo [INFO] Installing FileMaker Pro...
if exist "%~dp0filemaker\Setup.exe" (
    "%~dp0filemaker\Setup.exe" /s /qn
    echo [SUCCESS] FileMaker Pro installed.
) else (
    echo [INFO] No FileMaker installer in oem\filemaker, skipped.
)

:: Open files double-clicked on Linux (queued in \\tsclient\home\.queue) inside this desktop.
echo [INFO] Installing WinApps open queue...
mkdir "C:\ProgramData\WinApps" >nul 2>&1
copy /Y "%~dp0openqueue\open-queue.ps1" "C:\ProgramData\WinApps\open-queue.ps1" >nul
> "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\WinApps open queue.vbs" echo CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\ProgramData\WinApps\open-queue.ps1""", 0, False
echo [SUCCESS] Open queue installed.
