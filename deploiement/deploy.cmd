@echo off
REM =====================================================================
REM  Free-Motions - deploiement de l'image de reference (UEFI / GPT)
REM  1. partitionne le disque 0   2. applique W11-REF.wim   3. rend le disque bootable
REM  4. depose unattend.xml (nom du poste + OU)   5. depose SetupComplete.cmd (nettoyage)
REM =====================================================================
setlocal enabledelayedexpansion
cls
echo.
echo  === DEPLOIEMENT DE L'IMAGE DE REFERENCE ===
echo.
if not exist Z:\Images\W11-REF.wim (
    echo Image introuvable : Z:\Images\W11-REF.wim
    echo Capturer d'abord un poste de reference ^(choix 2 du menu^).
    pause
    goto :eof
)
if not exist Z:\Unattend\unattend.xml (
    echo Fichier de reponse introuvable : Z:\Unattend\unattend.xml
    pause
    goto :eof
)

set NOM=
set /p NOM=Nom du poste (ex : PAR-PCF001 pour un fixe, PAR-PCP001 pour un portable) : 
if "%NOM%"=="" goto :eof
echo.
echo Type de poste :  1 = Fixe    2 = Portable
set TYPE=
set /p TYPE=Choix : 
set OUTYPE=Fixes
if "%TYPE%"=="2" set OUTYPE=Portables

echo.
echo  Poste    : %NOM%
echo  OU       : OU=%OUTYPE%,OU=Ordinateurs,OU=PARIS
echo  Image    : Z:\Images\W11-REF.wim
echo.
echo  ATTENTION : le disque 0 de ce poste va etre ENTIEREMENT EFFACE.
set OK=
set /p OK=Tapez OUI pour continuer : 
if /i not "%OK%"=="OUI" goto :eof

echo.
echo === 1/5 Partitionnement du disque (UEFI / GPT) ===
diskpart /s Z:\Scripts\uefi.txt
if errorlevel 1 goto erreur

echo.
echo === 2/5 Application de l'image (plusieurs minutes) ===
dism /Apply-Image /ImageFile:Z:\Images\W11-REF.wim /Index:1 /ApplyDir:W:\
if errorlevel 1 goto erreur

echo.
echo === 3/5 Fichiers de demarrage UEFI ===
bcdboot W:\Windows /s S: /f UEFI
if errorlevel 1 goto erreur

echo.
echo === 4/5 Fichier de reponse (nom du poste + OU) ===
if not exist W:\Windows\Panther md W:\Windows\Panther
(for /f "usebackq delims=" %%L in ("Z:\Unattend\unattend.xml") do (
    set "LIGNE=%%L"
    set "LIGNE=!LIGNE:__NOMPOSTE__=%NOM%!"
    set "LIGNE=!LIGNE:__OUTYPE__=%OUTYPE%!"
    echo(!LIGNE!
)) > W:\Windows\Panther\unattend.xml
if errorlevel 1 goto erreur

echo.
echo === 5/5 Script de nettoyage de fin d'installation ===
if not exist W:\Windows\Setup\Scripts md W:\Windows\Setup\Scripts
copy /y Z:\Scripts\SetupComplete.cmd W:\Windows\Setup\Scripts\SetupComplete.cmd
if errorlevel 1 goto erreur

echo.
echo  ==========================================================
echo   Deploiement termine. Redemarrage dans 10 secondes.
echo   Ne pas appuyer sur F12 au redemarrage : le poste doit
echo   demarrer sur son disque pour finir l'installation.
echo  ==========================================================
ping -n 11 127.0.0.1 >nul
wpeutil reboot
goto :eof

:erreur
echo.
echo  ERREUR : lire le message ci-dessus. Deploiement interrompu.
pause
