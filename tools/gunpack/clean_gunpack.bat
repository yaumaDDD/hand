@echo off
rem Puts the content of a gun pack (sound, materials, models) to its place and deletes what
rem nothing uses. Lies in the content addon, next to its sound / materials / models folders,
rem together with the folder clean_gunpack.
rem
rem   double click           works out from the Lua what is used (the list that comes with it -
rem                          Remorseim and Z-City -, the Lua of this addon and of the other
rem                          addons in the same addons folder), moves misplaced files to their
rem                          place, shows how much is not used and, after Enter, DELETES it
rem   drop folders on it     the Lua in those folders (or .zip) counts as well
rem   clean_gunpack.bat --dry-run    changes nothing, writes the list only
rem   clean_gunpack.bat --keep       moves the files, deletes nothing
rem   clean_gunpack.bat --yes        deletes without asking
rem
rem Close the game first. What was deleted cannot be brought back: keep a copy of the addon.
rem clean_gunpack_report.txt lists everything. The work is done by clean_gunpack\clean_gunpack.py;
rem this file only finds a Python to run it with, and fetches a portable one when there is none.
setlocal
set "HERE=%~dp0"
set "TOOL=%HERE%clean_gunpack\clean_gunpack.py"
if not exist "%TOOL%" goto notool
if defined ZCG_PORTABLE_PYTHON goto portable

rem ---- a Python that is installed
py -3 -c "import sys; sys.exit(0 if sys.version_info[:2] > (3, 6) else 1)" >nul 2>nul
if not errorlevel 1 goto withpy
python -c "import sys; sys.exit(0 if sys.version_info[:2] > (3, 6) else 1)" >nul 2>nul
if not errorlevel 1 goto withpython

rem ---- none: a portable one, fetched once (about 11 MB), kept outside of the game
:portable
if not defined LOCALAPPDATA set "LOCALAPPDATA=%TEMP%"
set "PYDIR=%LOCALAPPDATA%\zcg_python"
if exist "%PYDIR%\python.exe" goto runportable
echo Python is not installed on this computer.
echo Fetching a portable copy from python.org (about 11 MB, only this once) ...
if not exist "%PYDIR%" mkdir "%PYDIR%"
if not exist "%PYDIR%" goto nopython
pushd "%PYDIR%"
curl.exe -L --fail --silent --show-error -o python.zip "https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip"
if errorlevel 1 goto powershell
tar.exe -xf python.zip
if errorlevel 1 goto powershell
goto fetched

:powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; Invoke-WebRequest -UseBasicParsing -Uri 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-embed-amd64.zip' -OutFile python.zip; Expand-Archive -Force -Path python.zip -DestinationPath ."
if errorlevel 1 goto nofetch

:fetched
del python.zip >nul 2>nul
popd
if not exist "%PYDIR%\python.exe" goto nopython

:runportable
"%PYDIR%\python.exe" -B "%TOOL%" %*
goto done

:withpy
py -3 -B "%TOOL%" %*
goto done

:withpython
python -B "%TOOL%" %*
goto done

:done
set "CODE=%ERRORLEVEL%"
echo.
if not defined ZCG_NO_PAUSE pause
exit /b %CODE%

:notool
echo The folder "clean_gunpack" with the scripts is not next to this file.
echo Put clean_gunpack.bat and the folder clean_gunpack side by side into the addon.
goto fail

:nofetch
popd
:nopython
echo.
echo A portable Python could not be fetched (no internet connection?).
echo Install Python from https://www.python.org/downloads/ with the option
echo "Add python.exe to PATH" ticked, then start this file again.

:fail
echo.
if not defined ZCG_NO_PAUSE pause
exit /b 1
