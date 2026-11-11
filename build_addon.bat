@echo off
rem Builds the Garry's Mod addon into build\zcity_csgo_gloves - see README.md.
rem Arguments are passed on to build_addon.py, for example:  build_addon.bat --zip
setlocal
cd /d "%~dp0"

set "PY="
py -3 -c "import sys; sys.exit(0 if sys.version_info[:2] > (3, 6) else 1)" >nul 2>nul
if not errorlevel 1 set "PY=py -3"
if defined PY goto build
python -c "import sys; sys.exit(0 if sys.version_info[:2] > (3, 6) else 1)" >nul 2>nul
if not errorlevel 1 set "PY=python"
if defined PY goto build

echo Python 3.7 or newer was not found.
echo Install it from https://www.python.org/downloads/ with the option
echo "Add python.exe to PATH" ticked, then start this file again.
goto fail

:build
rem The build runs the Lua of the clothing packs to learn which files it asks for
rem (tools\lua_names.py). That needs the lupa module; without it the addon is built all the
rem same, but sort_content.bat then knows fewer names - the build says "NOT RUN".
%PY% -c "import lupa" >nul 2>nul
if not errorlevel 1 goto run
echo Installing the lupa module to run the Lua of the clothing packs...
%PY% -m pip install --user lupa
echo.

:run
%PY% build_addon.py %*
if not errorlevel 3 goto finish
if errorlevel 4 goto finish

rem exit code 3: neither the py7zr module nor 7-Zip is available
echo.
echo Installing the py7zr module to unpack the archives...
%PY% -m pip install --user py7zr
if errorlevel 1 goto fail
echo.
%PY% build_addon.py %*

:finish
if errorlevel 1 goto fail
echo.
pause
exit /b 0

:fail
echo.
echo The addon was NOT built.
pause
exit /b 1
