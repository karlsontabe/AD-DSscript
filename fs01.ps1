# =====================================================================
#  Free-Motions - Lot 3 - Serveur de fichiers PAR-FS01
#  Domaine : free-motions-eq1.com  |  IP : 10.10.40.21/24  |  OU : PARIS\Serveurs
#  Carte Trello : Serveur de fichiers - FSRM, quotas, deduplication, DFS
#  + le "P" d'AGDLP : droits NTFS donnes UNIQUEMENT aux groupes DL_FS_
#  A executer LIGNE PAR LIGNE ou bloc par bloc, dans l'ordre.
#
#  PREREQUIS (Proxmox) : VM nommee nat-bai-...-PAR-FS01
#   - Windows Server 2022 (Server Core), 2 Go RAM, 2 vCPU
#   - Disque 1 : 32 Go (systeme)  |  Disque 2 : 20 Go (DONNEES - indispensable :
#     la deduplication ne fonctionne pas sur le disque systeme)
#   - Carte reseau VirtIO sur nat271e1l1 + ISO virtio-win en 2e lecteur CD
#
#  PARTIE A : A TAPER A LA MAIN (pas encore de reseau), comme pour DC02
#   - Pilote reseau : pnputil /add-driver D:\NetKVM\2k22\amd64\netkvm.inf /install
#   - Get-NetAdapter  (noter ifIndex)
#   - New-NetIPAddress -InterfaceIndex <ifIndex> -IPAddress 10.10.40.21 -PrefixLength 24 -DefaultGateway 10.10.40.254
#   - Set-DnsClientServerAddress -InterfaceIndex <ifIndex> -ServerAddresses 10.10.40.11,10.10.40.12
#   - nslookup free-motions-eq1.com     (on attend 10.10.40.11 et 10.10.40.12)
#   - New-Item -ItemType Directory -Path C:\Scripts
#   - $git = 'https://raw.githubusercontent.com/karlsontabe/AD-DSscript/main'
#   - Invoke-WebRequest "$git/fs01.ps1" -OutFile C:\Scripts\fs01.ps1 -UseBasicParsing
#   - notepad C:\Scripts\fs01.ps1
# =====================================================================


# ===================== PARTIE B - Heure, nom et jonction au domaine =====================

# --- B1. Heure : a moins de 5 min de DC01, sinon la jonction echoue (Kerberos)
Get-Date

# --- B2. Renommer ET joindre au domaine en une seule commande, puis redemarrer
#         -OUPath : le compte ordinateur est cree directement dans PARIS\Serveurs
#         Identifiant : FREEMOTIONS\t0-ktabe (ou FREEMOTIONS\Administrateur s'il est encore actif)
Add-Computer -DomainName 'free-motions-eq1.com' -NewName 'PAR-FS01' -OUPath 'OU=Serveurs,OU=PARIS,OU=FREE-MOTIONS,DC=free-motions-eq1,DC=com' -Credential (Get-Credential) -Restart

# --- B3. Apres redemarrage : se connecter avec un compte du DOMAINE (Autre utilisateur ->
#         FREEMOTIONS\t0-ktabe), SConfig -> 15, puis verifier :
(Get-CimInstance Win32_ComputerSystem) | Select Name, Domain, PartOfDomain


# ===================== PARTIE C - Disque de donnees =====================

# --- C1. Reperer le 2e disque (OperationalStatus Offline, PartitionStyle RAW, ~20 Go)
Get-Disk

# --- C2. L'initialiser, creer une partition sur toute la taille, lettre S: (S = Shares)
#         Remplacer 1 par le Number du disque de 20 Go vu en C1
Initialize-Disk -Number 1 -PartitionStyle GPT
New-Partition -DiskNumber 1 -UseMaximumSize -DriveLetter S
Format-Volume -DriveLetter S -FileSystem NTFS -NewFileSystemLabel 'DONNEES' -Confirm:$false

# --- C3. Verification
Get-Volume -DriveLetter S


# ===================== PARTIE D - Roles du serveur de fichiers =====================
#  FS-FileServer         : serveur de fichiers (partages SMB)
#  FS-Resource-Manager   : FSRM (quotas, filtrage de fichiers, rapports)
#  FS-Data-Deduplication : deduplication
#  FS-DFS-Namespace      : espace de noms DFS
Install-WindowsFeature FS-FileServer, FS-Resource-Manager, FS-Data-Deduplication, FS-DFS-Namespace -IncludeManagementTools


# ===================== PARTIE E - Arborescence par service =====================
$racine   = 'S:\Partages'
$services = 'Direction', 'Commercial', 'Technique', 'Informatique', 'Commun'
New-Item -ItemType Directory -Path $racine
foreach ($s in $services) { New-Item -ItemType Directory -Path "$racine\$s" }
Get-ChildItem $racine


# ===================== PARTIE F - Le "P" d'AGDLP : droits NTFS =====================
#  Regle : les droits sont donnes AUX GROUPES DL_ uniquement, jamais a un utilisateur ni a un GG_.
#  On utilise les SID des comptes integres pour ne pas dependre de la langue de Windows :
#   *S-1-5-32-544 = Administrateurs (local)   *S-1-5-18 = SYSTEM   *S-1-5-11 = Utilisateurs authentifies
#  Droits icacls : F = controle total   M = modification   RX = lecture et execution
#  (OI)(CI) = s'applique au dossier, aux sous-dossiers et aux fichiers
#  /inheritance:r = coupe l'heritage du dossier parent (on repart de zero)

# --- F1. Racine : les utilisateurs peuvent seulement la traverser (pas de (OI)(CI) pour eux)
icacls $racine /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-11:RX'

# --- F2. Un dossier = ses groupes DL (RW = modification, RO = lecture)
icacls "$racine\Direction"    /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' 'FREEMOTIONS\DL_FS_Direction_RW:(OI)(CI)M'
icacls "$racine\Commercial"   /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' 'FREEMOTIONS\DL_FS_Commercial_RW:(OI)(CI)M' 'FREEMOTIONS\DL_FS_Commercial_RO:(OI)(CI)RX'
icacls "$racine\Technique"    /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' 'FREEMOTIONS\DL_FS_Technique_RW:(OI)(CI)M' 'FREEMOTIONS\DL_FS_Technique_RO:(OI)(CI)RX'
icacls "$racine\Informatique" /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' 'FREEMOTIONS\DL_FS_Informatique_RW:(OI)(CI)M'
icacls "$racine\Commun"       /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' 'FREEMOTIONS\DL_FS_Commun_RW:(OI)(CI)M'

# --- F3. Verification : on ne doit voir QUE des groupes DL_ (plus Administrateurs et SYSTEM)
foreach ($s in $services) { icacls "$racine\$s" }


# ===================== PARTIE G - Partages SMB =====================
#  Bonne pratique : partage large (Utilisateurs authentifies en Modification), securite reelle par NTFS (partie F).
#  -FolderEnumerationMode AccessBased (ABE) : chacun ne VOIT que les dossiers auxquels il a droit.
$admins = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([System.Security.Principal.NTAccount]).Value
$auth   = (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-11')).Translate([System.Security.Principal.NTAccount]).Value
$admins
$auth
foreach ($s in $services) {
    New-SmbShare -Name $s -Path "$racine\$s" -FullAccess $admins -ChangeAccess $auth -FolderEnumerationMode AccessBased -Description "Partage $s - Free-Motions"
}
Get-SmbShare | Where-Object Name -in $services | Select Name, Path, FolderEnumerationMode


# ===================== PARTIE H - FSRM : quotas et filtrage =====================

# --- H1. Quotas stricts par service (le depot est refuse une fois la limite atteinte)
New-FsrmQuota -Path "$racine\Direction"    -Size 2GB -Description 'Quota Direction'
New-FsrmQuota -Path "$racine\Commercial"   -Size 5GB -Description 'Quota Commercial'
New-FsrmQuota -Path "$racine\Technique"    -Size 5GB -Description 'Quota Technique'
New-FsrmQuota -Path "$racine\Informatique" -Size 2GB -Description 'Quota Informatique'
New-FsrmQuota -Path "$racine\Commun"       -Size 5GB -Description 'Quota Commun'
Get-FsrmQuota | Select Path, @{n='Limite (Go)';e={$_.Size/1GB}}, @{n='Utilise (Mo)';e={[math]::Round($_.Usage/1MB,1)}}

# --- H2. Filtrage : blocage des fichiers audio et video sur tous les partages
#         On retrouve le groupe de fichiers "audio et video" par son contenu (*.mp3),
#         pour ne pas dependre de la langue de Windows
$multimedia = (Get-FsrmFileGroup | Where-Object { $_.IncludePattern -contains '*.mp3' }).Name
$multimedia
New-FsrmFileScreen -Path $racine -IncludeGroup $multimedia -Active -Description 'Blocage des fichiers multimedia'
Get-FsrmFileScreen | Select Path, IncludeGroup, Active

# --- H3. Test du filtrage : la creation d'un .mp3 doit etre REFUSEE (acces refuse)
New-Item -ItemType File -Path "$racine\Commun\test.mp3"

# --- H4. Rapport FSRM (livrable) : utilisation des quotas, genere immediatement
New-FsrmStorageReport -Name 'Rapport quotas Free-Motions' -Namespace @($racine) -ReportType QuotaUsage -Interactive
#         Le rapport HTML est depose dans C:\StorageReports\Interactive (a copier pour le dossier)


# ===================== PARTIE I - Deduplication =====================

# --- I1. Activer la deduplication sur S: (usage general)
Enable-DedupVolume -Volume 'S:' -UsageType Default
#         Pour la demonstration : traiter les fichiers tout de suite (par defaut : fichiers de plus de 3 jours)
Set-DedupVolume -Volume 'S:' -MinimumFileAgeDays 0

# --- I2. Jeu de test : un fichier de 50 Mo au contenu aleatoire, copie dans 3 services
#         (situation reelle : la meme presentation ou le meme catalogue enregistre par plusieurs services)
$data = New-Object byte[] (50MB)
(New-Object System.Random).NextBytes($data)
[System.IO.File]::WriteAllBytes("$racine\Commercial\catalogue-2026.pdf", $data)
Copy-Item "$racine\Commercial\catalogue-2026.pdf" "$racine\Technique\catalogue-2026.pdf"
Copy-Item "$racine\Commercial\catalogue-2026.pdf" "$racine\Commun\catalogue-2026.pdf"

# --- I3. Lancer l'optimisation et attendre la fin
Start-DedupJob -Volume 'S:' -Type Optimization -Wait

# --- I4. Resultat (livrable : taux de deduplication) - on attend environ 66 % (3 copies -> 1)
Get-DedupVolume -Volume 'S:' | Select Volume, SavedSpace, SavingsRate
Get-DedupStatus -Volume 'S:' | Select Volume, OptimizedFilesCount, InPolicyFilesCount, SavedSpace


# ===================== PARTIE J - Espace de noms DFS =====================
#  Les utilisateurs accederont a \\free-motions-eq1.com\Partages\<Service>
#  au lieu de \\PAR-FS01\<Service> : le nom ne change pas si le serveur change,
#  et Lyon (DFS-R, carte d'Arame) pourra ajouter sa propre cible.

# --- J1. Dossier et partage qui hebergent la racine de l'espace de noms
New-Item -ItemType Directory -Path 'S:\DFSRoots\Partages'
New-SmbShare -Name 'Partages' -Path 'S:\DFSRoots\Partages' -ReadAccess $auth -FullAccess $admins

# --- J2. Creer l'espace de noms de domaine (mode Windows Server 2008, DomainV2)
New-DfsnRoot -Path '\\free-motions-eq1.com\Partages' -TargetPath '\\PAR-FS01\Partages' -Type DomainV2 -Description 'Espace de noms Free-Motions'

# --- J3. Un dossier DFS par service, qui pointe vers le partage de PAR-FS01
foreach ($s in $services) {
    New-DfsnFolder -Path "\\free-motions-eq1.com\Partages\$s" -TargetPath "\\PAR-FS01\$s"
}

# --- J4. Verification
Get-DfsnFolder -Path '\\free-motions-eq1.com\Partages\*' | Select Path, State
Get-ChildItem '\\free-motions-eq1.com\Partages'


# ===================== PARTIE K - Recapitulatif (captures pour le dossier) =====================
Get-SmbShare | Where-Object Name -in ($services + 'Partages') | Select Name, Path
Get-FsrmQuota | Select Path, @{n='Limite (Go)';e={$_.Size/1GB}}
Get-DedupVolume -Volume 'S:' | Select Volume, SavingsRate
icacls "$racine\Commercial"
