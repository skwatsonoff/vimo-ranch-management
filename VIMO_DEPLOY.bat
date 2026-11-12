@echo off
rem Builds GitHub main in a clean temporary clone and deploys it to the
rem existing Firebase site (https://my-ranch-sync.web.app). 1.4.0 adds new
rem Firestore rules (shared animal cards, bull work records), so rules are
rem deployed together with hosting. The laptop working tree is not touched.
setlocal
set REPO=https://github.com/skwatsonoff/vimo-ranch-management.git
set WORK=%TEMP%\vimo_release
if exist "%WORK%" rmdir /s /q "%WORK%"
git clone --depth 1 --branch main %REPO% "%WORK%" || goto :fail
cd /d "%WORK%"
call flutter pub get || goto :fail
call flutter build web --release || goto :fail
call npm install --prefix "%WORK%\.firebase-sdk" --no-save --ignore-scripts firebase@12.19.0 || goto :fail
call node tools/web/prepare_release.mjs "%WORK%\.firebase-sdk\node_modules\firebase" || goto :fail
call firebase deploy --only hosting,firestore:rules --project my-ranch-sync || goto :fail
echo.
echo VIMO is live at https://my-ranch-sync.web.app
pause
exit /b 0
:fail
echo.
echo Deploy stopped. Nothing after the failing step was published.
pause
exit /b 1
