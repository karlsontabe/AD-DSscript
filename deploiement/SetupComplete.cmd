@echo off
REM =====================================================================
REM  Free-Motions - SetupComplete.cmd
REM  Execute automatiquement par Windows a la fin de l'installation,
REM  avant le premier ecran de connexion (la jonction au domaine est deja faite).
REM  Supprime les fichiers de reponse qui contiennent des mots de passe.
REM =====================================================================
del /f /q "%WINDIR%\Panther\unattend.xml" 2>nul
del /f /q "%WINDIR%\Panther\Unattend\unattend.xml" 2>nul
del /f /q "%WINDIR%\System32\Sysprep\unattend.xml" 2>nul
echo %DATE% %TIME% - fichiers de reponse supprimes >> "%WINDIR%\Setup\Scripts\SetupComplete.log"
