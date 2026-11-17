@echo off
rem Собирает ганпак Remorseim, беря ВСЁ только из папок самого аддона (sound / materials / models).
rem Лежит в аддоне с ганпаком, рядом с его папками контента, вместе с папкой clean_gunpack.
rem
rem   двойной клик    раскладывает по местам то, что лежит в sound, materials и models аддона
rem                   (в том числе сваленное в кучу и в нумерованных папках), добирает недостающее
rem                   из списков пака (tools/models.txt, sounds.txt) копиями файлов из самого
rem                   аддона. Игра, воркшоп (.gma), соседние аддоны и другие папки компа НЕ
rem                   трогаются вовсе; перетащенные на батник папки игнорируются.
rem   sort_own_gunpack.bat --dry-run    ничего не меняет, только пишет список
rem   ничего не удаляет вовсе: всё, что закинуто в аддон, остаётся
rem
rem Источник один - папки самого аддона, как в sort_own.bat для одежды. Отчёт - clean_gunpack_report.txt.
rem Работает clean_gunpack\clean_gunpack.py с ключом --own-only; этот файл только ищет, чем её
rem запустить, и передаёт ей лишь ключи с "--".
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
set "TOOL=%HERE%clean_gunpack\clean_gunpack.py"
if not exist "%TOOL%" set "TOOL=%HERE%tools\clean_gunpack.py"
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
"%PYDIR%\python.exe" -B "%TOOL%" --own-only --keep !ARGS!
goto done

:withpy
py -3 -B "%TOOL%" --own-only --keep !ARGS!
goto done

:withpython
python -B "%TOOL%" --own-only --keep !ARGS!
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
