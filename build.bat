@echo off
rem Builds awinput.exe with the C# compiler that ships with Windows (.NET Framework 4.x).
rem No SDK, Visual Studio or downloads needed.
setlocal
cd /d "%~dp0"
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
if not exist "%CSC%" ( echo Could not find csc.exe from .NET Framework 4.x. & exit /b 1 )

if not exist bin mkdir bin
"%CSC%" /nologo /target:winexe /optimize+ /platform:anycpu /out:bin\awinput.exe src\awinput.cs
if errorlevel 1 ( echo Build failed. & exit /b 1 )
echo Built bin\awinput.exe
if /i not "%~1"=="--no-shortcuts" call "%~dp0streamdeck\make-shortcuts.bat" "%~dp0bin"
