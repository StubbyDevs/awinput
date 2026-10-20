@echo off
rem Creates one .lnk per action next to awinput.exe. Point a Stream Deck
rem "System > Open" action at any of them. Usage: make-shortcuts.bat [folder-with-awinput.exe]
setlocal
set DIR=%~1
if "%DIR%"=="" set DIR=%~dp0..\bin
if not exist "%DIR%\awinput.exe" ( echo awinput.exe not found in "%DIR%". Run build.bat first. & exit /b 1 )

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$d = (Resolve-Path '%DIR%').Path; $ws = New-Object -ComObject WScript.Shell;" ^
  "foreach ($a in 'dp','hdmi1','hdmi2','toggle','cycle') {" ^
  "  $l = $ws.CreateShortcut((Join-Path $d ('awinput ' + $a + '.lnk')));" ^
  "  $l.TargetPath = (Join-Path $d 'awinput.exe'); $l.Arguments = $a; $l.WorkingDirectory = $d; $l.WindowStyle = 7; $l.Save();" ^
  "  Write-Host ('  ' + $l.FullName) }"
