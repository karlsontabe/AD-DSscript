# =====================================================================
#  Free-Motions - recuperation des fichiers de deploiement depuis GitHub
#  A lancer sur PAR-WDS01, PowerShell administrateur (en par-icoulibaly) :
#     .\recuperer-fichiers.ps1
#  Telecharge chaque fichier au bon endroit dans F:\Deploy et convertit
#  les fins de ligne au format Windows (indispensable pour les .cmd).
# =====================================================================
$git = 'https://raw.githubusercontent.com/karlsontabe/AD-DSscript/main/deploiement'

$fichiers = [ordered]@{
    'build-winpe.cmd'   = 'F:\Deploy\Scripts'
    'startnet.cmd'      = 'F:\Deploy\Scripts'
    'menu.cmd'          = 'F:\Deploy\Scripts'
    'deploy.cmd'        = 'F:\Deploy\Scripts'
    'capture.cmd'       = 'F:\Deploy\Scripts'
    'uefi.txt'          = 'F:\Deploy\Scripts'
    'SetupComplete.cmd' = 'F:\Deploy\Scripts'
    'unattend.xml'      = 'F:\Deploy\Unattend'
}

foreach ($f in $fichiers.Keys) {
    $dest = Join-Path $fichiers[$f] $f
    if ($f -eq 'unattend.xml' -and (Test-Path $dest)) {
        Write-Host "Conserve (deja present, mots de passe deja saisis) : $dest" -ForegroundColor Yellow
        continue
    }
    Invoke-WebRequest "$git/$f" -OutFile $dest -UseBasicParsing
    (Get-Content $dest) | Set-Content $dest -Encoding ASCII     # fins de ligne CRLF
    Write-Host "OK : $dest" -ForegroundColor Green
}

Get-ChildItem F:\Deploy\Scripts, F:\Deploy\Unattend | Select FullName, Length
