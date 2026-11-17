@echo off
rem Собирает всё нужное для Remorseim guns ТОЛЬКО из ваших папок.
rem Лежит в аддоне с ганпаком, рядом с его папками sound / materials / models,
rem вместе с папкой clean_gunpack.
rem
rem   перетащить папки на батник   всё нужное, чего нет в аддоне, копируется из этих папок
rem                                (их луа тоже читается); больше ниоткуда: игра, воркшоп и
rem                                соседние аддоны не трогаются вовсе
rem   двойной клик                 раскладывает по местам то, что уже лежит в аддоне, и
rem                                показывает, чего не хватает (не берёт ниоткуда)
rem   gather_gunpack.bat --dry-run ничего не меняет, только пишет список
rem
rem Ничего не удаляет: батник только приносит и расставляет. Полный список того, что сделано и
rem чего не нашлось, - в clean_gunpack_report.txt. Работает clean_gunpack\clean_gunpack.py с
rem ключами --no-game --no-neighbours --keep; этот файл только ищет, чем её запустить.
setlocal
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
"%PYDIR%\python.exe" -B "%TOOL%" --no-game --no-neighbours --keep %*
goto done

:withpy
py -3 -B "%TOOL%" --no-game --no-neighbours --keep %*
goto done

:withpython
python -B "%TOOL%" --no-game --no-neighbours --keep %*
goto done

:done
set "CODE=%ERRORLEVEL%"
echo.
if not defined ZCG_NO_PAUSE pause
exit /b %CODE%

:notool
echo Рядом с этим файлом нет папки "clean_gunpack" со скриптами.
echo Положите gather_gunpack.bat и папку clean_gunpack рядом в аддон с ганпаком.
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
