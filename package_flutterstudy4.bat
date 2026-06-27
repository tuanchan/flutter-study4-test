@echo off
setlocal

cd /d "%~dp0"

set "ZIP_NAME=flutterstudy4.zip"

if exist "%ZIP_NAME%" del /f /q "%ZIP_NAME%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path 'lib','pubspec.yaml' -DestinationPath '%ZIP_NAME%' -Force"

if errorlevel 1 (
    echo Failed to create %ZIP_NAME%.
    exit /b 1
)

echo Created %ZIP_NAME%.
