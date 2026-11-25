@echo off
REM =====================================================================
REM  Free-Motions - Deploiement des postes
REM  Fabrication du WinPE personnalise (boot.wim) pour WDS
REM  A lancer sur PAR-WDS01 dans une INVITE DE COMMANDES EN ADMINISTRATEUR :
REM     F:\Deploy\Scripts\build-winpe.cmd
REM  Resultat : F:\WinPE\media\sources\boot.wim  (a importer dans WDS)
REM =====================================================================

call "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\DandISetEnv.bat"

if exist F:\WinPE (
    echo Suppression de l'ancien dossier F:\WinPE...
    rd /s /q F:\WinPE
)

echo.
echo === 1. Copie des fichiers WinPE (copype) ===
call copype amd64 F:\WinPE || goto erreur

echo.
echo === 2. Montage de l'image boot.wim ===
dism /Mount-Image /ImageFile:F:\WinPE\media\sources\boot.wim /Index:1 /MountDir:F:\WinPE\mount || goto erreur

echo.
echo === 3. Pilotes VirtIO (si le CD virtio-win est en D:) ===
if exist D:\NetKVM\w11\amd64  dism /Image:F:\WinPE\mount /Add-Driver /Driver:D:\NetKVM\w11\amd64 /Recurse
if exist D:\vioscsi\w11\amd64 dism /Image:F:\WinPE\mount /Add-Driver /Driver:D:\vioscsi\w11\amd64 /Recurse
if exist D:\viostor\w11\amd64 dism /Image:F:\WinPE\mount /Add-Driver /Driver:D:\viostor\w11\amd64 /Recurse

echo.
echo === 4. Script de demarrage personnalise (startnet.cmd) ===
copy /y F:\Deploy\Scripts\startnet.cmd F:\WinPE\mount\Windows\System32\startnet.cmd || goto erreur

echo.
echo === 5. Enregistrement et demontage de l'image ===
dism /Unmount-Image /MountDir:F:\WinPE\mount /Commit || goto erreur

echo.
echo ==========================================================
echo  OK : F:\WinPE\media\sources\boot.wim est pret.
echo  Etape suivante : l'importer dans la console WDS
echo  (Images de demarrage, clic droit, Ajouter une image de demarrage).
echo ==========================================================
goto :eof

:erreur
echo.
echo ERREUR : lire le message ci-dessus.
echo Si l'image est restee montee, la liberer avec :
echo   dism /Unmount-Image /MountDir:F:\WinPE\mount /Discard
