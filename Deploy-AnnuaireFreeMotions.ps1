<#
.SYNOPSIS
    Lot 3 - Free-Motions : deploiement de la structure de l'annuaire Active Directory.

.DESCRIPTION
    Script idempotent (peut etre relance sans risque) qui cree, dans le domaine courant :
      1. (option -ConfigurerSites) les sites AD PARIS / LYON, leurs sous-reseaux et le lien de site ;
      2. le suffixe UPN public (nom DNS du domaine par defaut) utilise pour les connexions et la synchro M365 ;
      3. l'arborescence d'OU par site et par service ;
      4. les groupes globaux (GG_) et de domaine local (DL_) selon le modele AGDLP ;
      5. le compte de service svc-glpi (liaison LDAP en lecture seule pour GLPI) ;
      6. les 50 comptes utilisateurs a partir du fichier CSV.

    Le nom du domaine n'est PAS code en dur : il est lu avec Get-ADDomain.
    Les utilisateurs sont identifies par leur matricule (attribut employeeID) : un utilisateur
    deja present n'est jamais recree ni modifie.

    A executer sur PAR-DC01 (ou un poste RSAT) avec un compte membre de "Admins du domaine".

.PARAMETER CsvPath
    Fichier des utilisateurs (separateur ';', UTF-8).

.PARAMETER UpnSuffix
    Suffixe UPN / domaine de messagerie. Par defaut : le nom DNS du domaine

.PARAMETER ConfigurerSites
    Renomme Default-First-Site-Name en PARIS, cree le site LYON, les sous-reseaux et le lien de site.
    A faire AVANT la promotion du RODC de Lyon.

.PARAMETER ActiverCorbeille
    Active la corbeille Active Directory (operation irreversible, recommandee).

.EXAMPLE
    .\Deploy-AnnuaireFreeMotions.ps1 -ConfigurerSites -ActiverCorbeille

.NOTES
    ANSK - Projet Free-Motions - Lot 3 Services d'infrastructure
    Compatible Windows PowerShell 5.1 (Windows Server 2022).
#>
#Requires -Modules ActiveDirectory
[CmdletBinding()]
param(
    [string]$CsvPath    = (Join-Path $PSScriptRoot 'FM_Utilisateurs.csv'),
    [string]$UpnSuffix  = '',
    [string]$ExportPath = (Join-Path $PSScriptRoot ("FM_MotsDePasse_Initiaux_{0:yyyyMMdd-HHmm}.csv" -f (Get-Date))),
    [switch]$ConfigurerSites,
    [switch]$ActiverCorbeille
)

Import-Module ActiveDirectory
$ErrorActionPreference = 'Stop'

$LogDir = Join-Path $PSScriptRoot 'Logs'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }
Start-Transcript -Path (Join-Path $LogDir ("Deploy-Annuaire_{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))) | Out-Null

$Domain   = Get-ADDomain
$Forest   = Get-ADForest
$DomainDN = $Domain.DistinguishedName
if (-not $UpnSuffix) { $UpnSuffix = $Domain.DNSRoot }   # par defaut : le nom du domaine (free-motions-eq1.com)
Write-Host "Domaine cible : $($Domain.DNSRoot) ($($Domain.NetBIOSName)) - $DomainDN" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Referentiel
# ---------------------------------------------------------------------------
$Sites = [ordered]@{
    'PAR' = @{ OU = 'PARIS'; Services = @('Direction', 'Commercial-ADV', 'Technique', 'Informatique') }
    'LYS' = @{ OU = 'LYON';  Services = @('Commercial', 'Technique') }
}

$RootOU   = "OU=FREE-MOTIONS,$DomainDN"
$AdminOU  = "OU=ADMINISTRATION,$DomainDN"
$GG_OU    = "OU=Globaux,OU=Groupes,$RootOU"
$DL_OU    = "OU=Domaine-Local,OU=Groupes,$RootOU"
$SvcOU    = "OU=Comptes-Service,$AdminOU"

# ---------------------------------------------------------------------------
# Fonctions utilitaires
# ---------------------------------------------------------------------------
function Write-Step([string]$Text) { Write-Host "`n=== $Text ===" -ForegroundColor Yellow }
function Write-Ok([string]$Text)   { Write-Host "  [+] $Text" -ForegroundColor Green }
function Write-Skip([string]$Text) { Write-Host "  [=] $Text (deja present)" -ForegroundColor DarkGray }

function Get-FilterValue([string]$Value) { $Value -replace "'", "''" }

function New-FMOU {
    param([string]$Name, [string]$Path, [string]$Description = '')
    $existing = Get-ADOrganizationalUnit -Filter "Name -eq '$(Get-FilterValue $Name)'" -SearchBase $Path -SearchScope OneLevel
    if ($existing) { Write-Skip "OU=$Name,$Path"; return }
    New-ADOrganizationalUnit -Name $Name -Path $Path -Description $Description -ProtectedFromAccidentalDeletion $true
    Write-Ok "OU=$Name,$Path"
}

function New-FMGroup {
    param([string]$Name, [ValidateSet('Global', 'DomainLocal')] [string]$Scope, [string]$Path, [string]$Description)
    if (Get-ADGroup -Filter "Name -eq '$(Get-FilterValue $Name)'") { Write-Skip $Name; return }
    New-ADGroup -Name $Name -SamAccountName $Name -GroupScope $Scope -GroupCategory Security `
                -Path $Path -Description $Description
    Write-Ok "$Name ($Scope)"
}

$Script:Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
function Get-FMRandomIndex([int]$Max) {
    $bytes = New-Object byte[] 4
    $Script:Rng.GetBytes($bytes)
    [int]([BitConverter]::ToUInt32($bytes, 0) % [uint32]$Max)
}
function New-FMPassword([int]$Length = 14) {
    # Sans caracteres ambigus (0/O, 1/l/I) pour faciliter la remise du mot de passe
    $sets = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!#%*?-+=')
    $all  = -join $sets
    $chars = New-Object System.Collections.Generic.List[char]
    foreach ($s in $sets) { $chars.Add($s[(Get-FMRandomIndex $s.Length)]) }
    while ($chars.Count -lt $Length) { $chars.Add($all[(Get-FMRandomIndex $all.Length)]) }
    -join ($chars | Sort-Object { Get-FMRandomIndex 100000 })
}

function ConvertTo-FMLogin([string]$Prenom, [string]$Nom) {
    # prenom.nom, minuscules, sans accents, espaces ni apostrophes, 20 caracteres max
    $clean = {
        param($s)
        $d  = $s.Normalize([Text.NormalizationForm]::FormD)
        $sb = New-Object System.Text.StringBuilder
        foreach ($c in $d.ToCharArray()) {
            if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
        }
        ($sb.ToString().ToLower() -replace "[\s']", '') -replace '[^a-z-]', ''
    }
    $login = '{0}.{1}' -f (& $clean $Prenom), (& $clean $Nom)
    if ($login.Length -gt 20) { $login = $login.Substring(0, 20) }
    $login
}

# ---------------------------------------------------------------------------
# 1. Sites et services
# ---------------------------------------------------------------------------
if ($ConfigurerSites) {
    Write-Step 'Sites et services Active Directory'

    $default = Get-ADReplicationSite -Filter "Name -eq 'Default-First-Site-Name'"
    if ($default) {
        Rename-ADObject -Identity $default.DistinguishedName -NewName 'PARIS'
        Write-Ok 'Default-First-Site-Name renomme en PARIS'
    }
    if (-not (Get-ADReplicationSite -Filter "Name -eq 'PARIS'")) {
        New-ADReplicationSite -Name 'PARIS' -Description 'Siege - Paris (PAR-DC01, PAR-DC02)'; Write-Ok 'Site PARIS'
    }
    Set-ADReplicationSite -Identity 'PARIS' -Description 'Siege - Paris (PAR-DC01, PAR-DC02)'
    if (-not (Get-ADReplicationSite -Filter "Name -eq 'LYON'")) {
        New-ADReplicationSite -Name 'LYON' -Description 'Agence - Lyon (LYS-RODC01)'; Write-Ok 'Site LYON'
    } else { Write-Skip 'Site LYON' }

    $subnets = @(
        @{ Name = '10.10.0.0/16'; Site = 'PARIS'; Location = 'Paris - LAN (VLAN 10 a 60)' },
        @{ Name = '10.99.0.0/24'; Site = 'PARIS'; Location = 'Paris - VPN nomades (termine sur FW-PAR01)' },
        @{ Name = '10.20.0.0/16'; Site = 'LYON';  Location = 'Lyon - LAN (VLAN 110, 140)' }
    )
    foreach ($s in $subnets) {
        if (Get-ADReplicationSubnet -Filter "Name -eq '$($s.Name)'") { Write-Skip "Sous-reseau $($s.Name)"; continue }
        New-ADReplicationSubnet -Name $s.Name -Site $s.Site -Location $s.Location
        Write-Ok "Sous-reseau $($s.Name) -> $($s.Site)"
    }

    $link = Get-ADReplicationSiteLink -Filter "Name -eq 'DEFAULTIPSITELINK'"
    if ($link) { Rename-ADObject -Identity $link.DistinguishedName -NewName 'LIEN-PARIS-LYON'; Write-Ok 'DEFAULTIPSITELINK renomme en LIEN-PARIS-LYON' }
    if (-not (Get-ADReplicationSiteLink -Filter "Name -eq 'LIEN-PARIS-LYON'")) {
        New-ADReplicationSiteLink -Name 'LIEN-PARIS-LYON' -SitesIncluded 'PARIS', 'LYON' -InterSiteTransportProtocol IP
    }
    $lnk     = Get-ADReplicationSiteLink -Identity 'LIEN-PARIS-LYON' -Properties SitesIncluded
    $present = @($lnk.SitesIncluded | ForEach-Object { (($_ -split ',')[0]) -replace '^CN=', '' })
    $missing = @('PARIS', 'LYON' | Where-Object { $present -notcontains $_ })
    if ($missing.Count -gt 0) { Set-ADReplicationSiteLink -Identity 'LIEN-PARIS-LYON' -SitesIncluded @{ Add = $missing } }
    Set-ADReplicationSiteLink -Identity 'LIEN-PARIS-LYON' -Cost 100 -ReplicationFrequencyInMinutes 15 `
        -Description 'Via VPN IPsec FW-PAR01 <-> FW-LYS01'
    Write-Ok 'Lien LIEN-PARIS-LYON : cout 100, replication toutes les 15 min'
}

# ---------------------------------------------------------------------------
# 2. Corbeille AD et suffixe UPN
# ---------------------------------------------------------------------------
if ($ActiverCorbeille) {
    Write-Step 'Corbeille Active Directory'
    $rb = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'"
    if ($rb.EnabledScopes.Count -gt 0) { Write-Skip 'Corbeille AD' }
    else {
        Enable-ADOptionalFeature -Identity $rb -Scope ForestOrConfigurationSet -Target $Forest.Name -Confirm:$false
        Write-Ok 'Corbeille AD activee'
    }
}

Write-Step "Suffixe UPN $UpnSuffix"
if ($Domain.DNSRoot -ieq $UpnSuffix -or $Forest.UPNSuffixes -contains $UpnSuffix) { Write-Skip "Suffixe $UpnSuffix" }
else { Set-ADForest -Identity $Forest -UPNSuffixes @{ Add = $UpnSuffix }; Write-Ok "Suffixe $UpnSuffix ajoute" }

# ---------------------------------------------------------------------------
# 3. Arborescence des OU
# ---------------------------------------------------------------------------
Write-Step 'Unites d''organisation'
New-FMOU 'ADMINISTRATION'  $DomainDN 'Objets a privileges - acces restreint a l''equipe IT'
New-FMOU 'Comptes-Admin'   $AdminOU  'Comptes adm-prenom.nom (jamais utilises pour la bureautique)'
New-FMOU 'Comptes-Service' $AdminOU  'Comptes svc-application'
New-FMOU 'Groupes-Admin'   $AdminOU  'Groupes de delegation et d''administration'

New-FMOU 'FREE-MOTIONS' $DomainDN 'Racine des objets de l''entreprise Free-Motions'
foreach ($code in $Sites.Keys) {
    $siteOU = $Sites[$code].OU
    $sitePath = "OU=$siteOU,$RootOU"
    New-FMOU $siteOU $RootOU "Site de $siteOU"
    New-FMOU 'Utilisateurs' $sitePath "Comptes utilisateurs - $siteOU"
    foreach ($svc in $Sites[$code].Services) { New-FMOU $svc "OU=Utilisateurs,$sitePath" "Service $svc - $siteOU" }
    New-FMOU 'Ordinateurs' $sitePath "Postes de travail - $siteOU"
    New-FMOU 'Fixes'       "OU=Ordinateurs,$sitePath" "Postes fixes $code-PCFnnn"
    New-FMOU 'Portables'   "OU=Ordinateurs,$sitePath" "Portables nomades $code-PCPnnn"
    New-FMOU 'Serveurs'    $sitePath "Serveurs membres - $siteOU (hors controleurs de domaine)"
}
New-FMOU 'Groupes'       $RootOU 'Groupes de securite metier'
New-FMOU 'Globaux'       "OU=Groupes,$RootOU" 'GG_ : regroupent des utilisateurs (role / service)'
New-FMOU 'Domaine-Local' "OU=Groupes,$RootOU" 'DL_ : portent les droits sur une ressource'
New-FMOU 'Desactives'    $RootOU 'Comptes des collaborateurs partis (conservation 90 jours)'

# ---------------------------------------------------------------------------
# 4. Groupes (AGDLP)
# ---------------------------------------------------------------------------
Write-Step 'Groupes globaux (GG_)'
foreach ($code in $Sites.Keys) {
    New-FMGroup "GG_${code}_Utilisateurs" Global $GG_OU "Tous les utilisateurs du site $($Sites[$code].OU)"
    foreach ($svc in $Sites[$code].Services) { New-FMGroup "GG_${code}_$svc" Global $GG_OU "Service $svc - $($Sites[$code].OU)" }
}
New-FMGroup 'GG_FM_Nomades'      Global $GG_OU 'Utilisateurs equipes d''un portable - acces VPN nomades'
New-FMGroup 'GG_LYS_Ordinateurs' Global $GG_OU 'Postes de Lyon - mise en cache autorisee sur LYS-RODC01'
New-FMGroup 'GG_ADM_Infra'       Global "OU=Groupes-Admin,$AdminOU" 'Administrateurs de l''infrastructure (comptes adm-)'

Write-Step 'Groupes de domaine local (DL_)'
$DL = [ordered]@{
    'DL_FS_Direction_RW'      = @{ D = 'PAR-FS01 \Direction - modification';        M = @('GG_PAR_Direction') }
    'DL_FS_Commercial_RW'     = @{ D = 'PAR-FS01 \Commercial - modification';       M = @('GG_PAR_Commercial-ADV', 'GG_LYS_Commercial') }
    'DL_FS_Commercial_RO'     = @{ D = 'PAR-FS01 \Commercial - lecture';            M = @('GG_PAR_Direction') }
    'DL_FS_Technique_RW'      = @{ D = 'PAR-FS01 \Technique - modification';        M = @('GG_PAR_Technique', 'GG_LYS_Technique') }
    'DL_FS_Technique_RO'      = @{ D = 'PAR-FS01 \Technique - lecture';             M = @('GG_PAR_Commercial-ADV', 'GG_LYS_Commercial') }
    'DL_FS_Informatique_RW'   = @{ D = 'PAR-FS01 \Informatique - modification';     M = @('GG_PAR_Informatique') }
    'DL_FS_Commun_RW'         = @{ D = 'PAR-FS01 \Commun - modification (tous)';    M = @('GG_PAR_Utilisateurs', 'GG_LYS_Utilisateurs') }
    'DL_RDS_Utilisateurs'     = @{ D = 'PAR-RDS01 - ouverture de session RDS';      M = @('GG_PAR_Utilisateurs', 'GG_LYS_Utilisateurs') }
    'DL_VPN_Nomades'          = @{ D = 'FW-PAR01 - authentification VPN nomades';   M = @('GG_FM_Nomades') }
    'DL_GLPI_Utilisateurs'    = @{ D = 'SRV-GLPI - import LDAP (profil Self-Service)'; M = @('GG_PAR_Utilisateurs', 'GG_LYS_Utilisateurs') }
    'DL_GLPI_Techniciens'     = @{ D = 'SRV-GLPI - import LDAP (profil Technicien)';   M = @('GG_PAR_Informatique') }
}
foreach ($name in $DL.Keys) { New-FMGroup $name DomainLocal $DL_OU $DL[$name].D }

Write-Step 'Imbrication AGDLP (GG -> DL)'
foreach ($name in $DL.Keys) {
    Add-ADGroupMember -Identity $name -Members $DL[$name].M
    Write-Ok "$name <- $($DL[$name].M -join ', ')"
}
# Politique de replication des mots de passe du RODC de Lyon (si deja promu)
$rodc = Get-ADDomainController -Filter { IsReadOnly -eq $true } | Where-Object { $_.Site -eq 'LYON' }
foreach ($r in $rodc) {
    Add-ADDomainControllerPasswordReplicationPolicy -Identity $r.Name -AllowedList 'GG_LYS_Utilisateurs', 'GG_LYS_Ordinateurs'
    Write-Ok "PRP $($r.Name) : GG_LYS_Utilisateurs et GG_LYS_Ordinateurs autorises a la mise en cache"
}

# ---------------------------------------------------------------------------
# 5. Compte de service GLPI
# ---------------------------------------------------------------------------
Write-Step 'Comptes de service'
$export = New-Object System.Collections.Generic.List[object]
if (Get-ADUser -Filter "SamAccountName -eq 'svc-glpi'") { Write-Skip 'svc-glpi' }
else {
    $pass = New-FMPassword 24
    New-ADUser -Name 'svc-glpi' -SamAccountName 'svc-glpi' -UserPrincipalName "svc-glpi@$UpnSuffix" `
        -DisplayName 'Service - GLPI (liaison LDAP)' -Description 'Lecture seule de l''annuaire pour SRV-GLPI - ne pas utiliser en session' `
        -Path $SvcOU -AccountPassword (ConvertTo-SecureString $pass -AsPlainText -Force) `
        -Enabled $true -PasswordNeverExpires $true -CannotChangePassword $true
    $export.Add([pscustomobject]@{ Matricule = '-'; NomComplet = 'svc-glpi'; Login = 'svc-glpi'; UPN = "svc-glpi@$UpnSuffix"; MotDePasseInitial = $pass })
    Write-Ok 'svc-glpi cree (OU Comptes-Service)'
}

# ---------------------------------------------------------------------------
# 6. Utilisateurs
# ---------------------------------------------------------------------------
Write-Step "Utilisateurs depuis $CsvPath"
$users = Import-Csv -Path $CsvPath -Delimiter ';' -Encoding UTF8
$created = 0; $skipped = 0

foreach ($u in $users) {
    $code = $u.Site.Trim().ToUpper()
    if (-not $Sites.Contains($code))                 { throw "Site inconnu '$($u.Site)' pour $($u.Matricule)" }
    if ($Sites[$code].Services -notcontains $u.Service) { throw "Service inconnu '$($u.Service)' pour $($u.Matricule)" }

    $existing = Get-ADUser -Filter "EmployeeID -eq '$($u.Matricule)'"
    if ($existing) { Write-Skip "$($u.Matricule) $($existing.SamAccountName)"; $skipped++; continue }

    $login = if ($u.Login) { $u.Login.Trim().ToLower() } else { ConvertTo-FMLogin $u.Prenom $u.Nom }
    if (Get-ADUser -Filter "SamAccountName -eq '$login'") {
        throw "Le login $login existe deja pour un autre matricule - corriger la colonne Login de $($u.Matricule)"
    }

    $ou          = "OU=$($u.Service),OU=Utilisateurs,OU=$($Sites[$code].OU),$RootOU"
    $displayName = '{0} {1}' -f $u.Prenom, $u.Nom.ToUpper()
    $cn          = $displayName
    if (Get-ADObject -Filter "Name -eq '$(Get-FilterValue $cn)'" -SearchBase $ou -SearchScope OneLevel) { $cn = "$displayName ($login)" }
    $upn         = "$login@$UpnSuffix"
    $pass         = New-FMPassword 14

    $params = @{
        Name                  = $cn
        GivenName             = $u.Prenom
        Surname               = $u.Nom
        DisplayName           = $displayName
        SamAccountName        = $login
        UserPrincipalName     = $upn
        EmailAddress          = $upn
        EmployeeID            = $u.Matricule
        Title                 = $u.Fonction
        Department            = $u.Service
        Office                = $Sites[$code].OU
        Company               = 'Free-Motions'
        Path                  = $ou
        AccountPassword       = (ConvertTo-SecureString $pass -AsPlainText -Force)
        Enabled               = $true
        ChangePasswordAtLogon = $true
    }
    New-ADUser @params

    Add-ADGroupMember -Identity "GG_${code}_Utilisateurs"   -Members $login
    Add-ADGroupMember -Identity "GG_${code}_$($u.Service)"  -Members $login
    if ($u.Nomade -eq 'O') { Add-ADGroupMember -Identity 'GG_FM_Nomades' -Members $login }

    $export.Add([pscustomobject]@{ Matricule = $u.Matricule; NomComplet = $displayName; Login = $login; UPN = $upn; MotDePasseInitial = $pass })
    Write-Ok "$($u.Matricule) $login -> $($Sites[$code].OU)\$($u.Service)"
    $created++
}

if ($export.Count -gt 0) {
    $export | Export-Csv -Path $ExportPath -Delimiter ';' -NoTypeInformation -Encoding UTF8
    Write-Host "`nMots de passe initiaux exportes : $ExportPath" -ForegroundColor Magenta
    Write-Host 'A remettre aux utilisateurs puis SUPPRIMER ce fichier (changement impose a la 1re connexion).' -ForegroundColor Magenta
}

Write-Step 'Bilan'
Write-Host "  Utilisateurs crees : $created - deja presents : $skipped - total CSV : $($users.Count)"
Write-Host '  Lancer ensuite .\Test-AnnuaireFreeMotions.ps1 pour le controle de conformite.'
Stop-Transcript | Out-Null
