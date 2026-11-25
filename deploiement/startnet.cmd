@echo off
REM =====================================================================
REM  Free-Motions - startnet.cmd (integre dans le WinPE personnalise)
REM  Initialise WinPE, connecte le partage de deploiement avec le compte
REM  du technicien, puis lance le menu stocke sur le partage.
REM  Aucun mot de passe n'est stocke dans l'image de demarrage.
REM =====================================================================
wpeinit
wpeutil SetKeyboardLayout 040c:0000040c
wpeutil WaitForNetwork
cls
echo.
echo  ==========================================================
echo   ANSK - Deploiement des postes Free-Motions
echo  ==========================================================
echo.

:connexion
set TECH=
set /p TECH=Identifiant du technicien (ex : par-icoulibaly) : 
if "%TECH%"=="" goto connexion
net use Z: \\PAR-WDS01.free-motions-eq1.com\Deploy$ /user:FREEMOTIONS\%TECH% *
if errorlevel 1 (
    echo Connexion refusee ou serveur injoignable. Nouvel essai.
    goto connexion
)
call Z:\Scripts\menu.cmd
