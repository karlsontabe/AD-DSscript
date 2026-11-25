@echo off
REM =====================================================================
REM  Free-Motions - capture de l'image de reference
REM  Le poste de reference doit avoir ete generalise AVANT :
REM     C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
REM  L'ancienne image est conservee sous W11-REF-precedente.wim
REM =====================================================================
setlocal
cls
echo.
echo  === CAPTURE DE L'IMAGE DE REFERENCE ===
echo.
set SRC=
for %%D in (C D E F G H I J K L M N O P Q R S T U V W) do (
    if exist %%D:\Windows\System32\config\SYSTEM set SRC=%%D:
)
if "%SRC%"=="" (
    echo Aucune partition Windows trouvee sur ce poste.
    pause
    goto :eof
)
echo  Partition Windows detectee : %SRC%
echo  Destination               : Z:\Images\W11-REF.wim
echo.
set OK=
set /p OK=Tapez OUI pour lancer la capture : 
if /i not "%OK%"=="OUI" goto :eof

if exist Z:\Images\W11-REF.wim (
    if exist Z:\Images\W11-REF-precedente.wim del /f /q Z:\Images\W11-REF-precedente.wim
    ren Z:\Images\W11-REF.wim W11-REF-precedente.wim
)

echo.
echo === Capture en cours (10 a 30 minutes) ===
dism /Capture-Image /ImageFile:Z:\Images\W11-REF.wim /CaptureDir:%SRC%\ /Name:"W11-REF Free-Motions" /Description:"Windows 11 Pro - image de reference ANSK" /Compress:max /CheckIntegrity /Verify
if errorlevel 1 (
    echo ERREUR pendant la capture : lire le message ci-dessus.
    pause
    goto :eof
)
echo.
echo  Capture terminee : Z:\Images\W11-REF.wim
pause
