@echo off
rem Раскладывает контент аддона внешности, беря ВСЁ только из папок самого аддона.
rem Лежит в аддоне, рядом с его папками materials и models, вместе с папкой sort_content.
rem
rem   двойной клик    раскладывает по местам то, что лежит в materials и models аддона (в том
rem                   числе сваленное в кучу и в нумерованных папках), добирает недостающие
rem                   имена копиями файлов из самого аддона и пишет sh_found.lua / sh_baked.lua
rem                   для игры. Игра, воркшоп (.gma), соседние аддоны и другие папки компа НЕ
rem                   трогаются вовсе; перетащенные на батник папки игнорируются.
rem   sort_own.bat --dry-run        ничего не меняет, только пишет список
rem   ничего не удаляет и ничего не откладывает: папка _not_used тоже раскладывается по своим
rem   путям в аддоне - игра ищет файл по точному пути, а не по именам из Lua
rem
rem Закройте игру перед запуском: она держит открытыми свои файлы. Отчёт - в
rem sort_content_report.txt. Работает sort_content\sort_content.py с ключом --own-only;
rem этот файл только ищет, чем её запустить, и передаёт ей лишь ключи с "--".
setlocal EnableDelayedExpansion
set "ARGS="
:args
if "%~1"=="" goto argsdone
set "ONE=%~1"
if "!ONE:~0,2!"=="--" set "ARGS=!ARGS! "%~1""
shift
goto args
:argsdone
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
"%PYDIR%\python.exe" -B "%TOOL%" --own-only --keep-unused --use-not-used !ARGS!
goto done

:withpy
py -3 -B "%TOOL%" --own-only --keep-unused --use-not-used !ARGS!
goto done

:withpython
python -B "%TOOL%" --own-only --keep-unused --use-not-used !ARGS!
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
