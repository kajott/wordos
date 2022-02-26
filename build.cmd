@echo off
set WORDSOURCE=classic
if "%1"=="classic" set WORDSOURCE=classic
if "%1"=="nyt" set WORDSOURCE=nyt
if "%1"=="distclean" goto distclean
if "%1"=="clean" goto clean

:install_prerequisites
if exist yasm.exe goto have_yasm
curl -oyasm.exe http://www.tortall.net/projects/yasm/releases/yasm-1.3.0-win32.exe
if errorlevel 1 goto end
:have_yasm

:build
if not exist wordlist.inc py wordlist.py %WORDSOURCE%
if errorlevel 1 goto end
yasm -fbin -owordos.com -lwordos.lst wordos.asm
if errorlevel 1 goto end
if "%1"=="test" goto test
goto end

:test
if not exist dosbox.exe goto dosboxinfo
dosbox wordos.com
goto end

:dosboxinfo
echo DOSBox isn't installed, and for complicated reasons (the only official DOSBox
echo download is an .exe installer, which can only be opened by the 7-zip GUI, but
echo not the command-line versions), automated download isn't scriptable. So you
echo have to install it by hand:
echo 1. download the latest Win32 installer from
echo    https://sourceforge.net/projects/dosbox/files/dosbox/
echo 2. don't install; just open it in the 7-Zip GUI (right click, open as archive)
echo 3. extract dosbox.exe and the SDL*.dll files into the WorDOS source directory
echo 4. to enable debugging, overwrite dosbox.exe with this one:
echo    http://source.dosbox.com/dosbox-74-3-debug.exe
goto end

:distclean
del yasm.exe

:clean
del wordlist.inc
del wordos.com
del wordos.lst
goto end

:end