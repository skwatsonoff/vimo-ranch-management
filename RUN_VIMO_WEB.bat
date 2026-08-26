@echo off
setlocal
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found. Install Flutter and add it to PATH first.
  pause
  exit /b 1
)

echo Preparing VIMO...
call flutter pub get
if errorlevel 1 (
  echo.
  echo Package setup failed. Check your internet connection and try again.
  pause
  exit /b 1
)

echo.
echo Opening VIMO in Chrome...
call flutter run -d chrome

pause
