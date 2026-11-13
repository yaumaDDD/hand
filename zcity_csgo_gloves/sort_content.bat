@echo off
rem Puts the materials and models of clothing addons where the game looks for them.
rem
rem   double click           sorts what lies in the materials and models folders of this addon
rem   drop folders on it     also takes in the content of those folders (or .zip archives)
rem   drop the game on it    (the folder GarrysMod) - nothing is taken from it: the files the addon
rem                          lacks are looked for in it. The game is found without that as well,
rem                          when the addon lies in its addons folder or Steam has it.
rem
rem The content can be thrown in the way it was collected: the materials and models folders of
rem other addons as materials1, materials2, models1 ... - into materials, into models, into both,
rem or beside them. Every folder and subfolder is gone through: the files of models end up below
rem models, materials and textures below materials, and the numbered folders go away.
rem Afterwards it tells what it went through - how many folders, how deep - goes through the
rem two folders once more, and tells what they hold and which files are missing for real.
rem
rem Close the game first: it keeps the files it uses open. At the end the content that the
rem clothes do not use and that is no clothing (props, weapons, models nobody wears ...) is
rem DELETED, and so is the folder _not_used; sort_content_report.txt lists what went.
rem   sort_content.bat --keep-unused     deletes nothing
rem See the README, "sort_content.bat". The work is done by sort_content\sort_content.py; this file only finds
rem a Python to run it with, and fetches a portable one from python.org when there is none.
setlocal
set "HERE=%~dp0"
set "TOOL=%HERE%sort_content\sort_content.py"
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
echo The folder "sort_content" with the scripts is not next to this file.
echo Take the whole folder zcity_csgo_gloves out of the release archive again.
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
