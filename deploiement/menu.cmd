@echo off
REM =====================================================================
REM  Free-Motions - menu de deploiement (stocke sur \\PAR-WDS01\Deploy$\Scripts)
REM  Modifiable sans reconstruire WinPE.
REM =====================================================================
:menu
cls
echo.
echo  ==========================================================
echo   ANSK - Deploiement des postes Free-Motions
echo  ==========================================================
echo.
echo   1 - Deployer l'image de reference sur ce poste (EFFACE LE DISQUE)
echo   2 - Capturer ce poste comme image de reference
echo   3 - Invite de commandes
echo   4 - Redemarrer
echo   5 - Eteindre
echo.
set CHOIX=
set /p CHOIX=Votre choix : 
if "%CHOIX%"=="1" call Z:\Scripts\deploy.cmd
if "%CHOIX%"=="2" call Z:\Scripts\capture.cmd
if "%CHOIX%"=="3" cmd
if "%CHOIX%"=="4" wpeutil reboot
if "%CHOIX%"=="5" wpeutil shutdown
goto menu
