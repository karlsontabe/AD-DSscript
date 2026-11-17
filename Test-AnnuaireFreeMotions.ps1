<#
.SYNOPSIS
    Lot 3 - Free-Motions : controle de conformite de l'annuaire (recette).

.DESCRIPTION
    Verifie, sans rien modifier, que l'annuaire correspond au schema et aux conventions du Lot 3 :
    controleurs de domaine, FSMO, sites, OU, groupes, comptes, conventions de nommage.
    Chaque controle affiche OK / KO ; le resume final sert de preuve de recette (capture du dossier).

.NOTES
    ANSK - Projet Free-Motions - Lot 3. Lecture seule. Compatible Windows PowerShell 5.1.
#>
#Requires -Modules ActiveDirectory
[CmdletBinding()]
param(
    [int]$NombreUtilisateursAttendu = 50,
    [string]$UpnSuffix = ''
)
Import-Module ActiveDirectory
$Domain   = Get-ADDomain
$Forest   = Get-ADForest
$DomainDN = $Domain.DistinguishedName
if (-not $UpnSuffix) { $UpnSuffix = $Domain.DNSRoot }   # par defaut : le nom du domaine (free-motions-eq1.com)
$RootOU   = "OU=FREE-MOTIONS,$DomainDN"
$Results  = New-Object System.Collections.Generic.List[object]

function Test-Item([string]$Categorie, [string]$Controle, [bool]$Ok, [string]$Detail = '') {
    $Results.Add([pscustomobject]@{ Categorie = $Categorie; Controle = $Controle; Resultat = $(if ($Ok) { 'OK' } else { 'KO' }); Detail = $Detail })
}

Write-Host "Recette annuaire - $($Domain.DNSRoot) - $(Get-Date -Format 'dd/MM/yyyy HH:mm')" -ForegroundColor Cyan

# --- Foret et controleurs de domaine -------------------------------------------------
$dcs = Get-ADDomainController -Filter *
$rw  = @($dcs | Where-Object { -not $_.IsReadOnly -and $_.Site -eq 'PARIS' })
Test-Item 'Foret' 'Niveau fonctionnel foret >= 2016' ([string]$Forest.ForestMode -match '2016|2025') $Forest.ForestMode
Test-Item 'Foret' 'Niveau fonctionnel domaine >= 2016' ([string]$Domain.DomainMode -match '2016|2025') $Domain.DomainMode
Test-Item 'DC' '2 DC en ecriture sur le site PARIS' ($rw.Count -ge 2) (($rw | ForEach-Object Name) -join ', ')
Test-Item 'DC' 'Tous les DC de Paris sont catalogue global' (@($rw | Where-Object { -not $_.IsGlobalCatalog }).Count -eq 0)
$rodc = @($dcs | Where-Object IsReadOnly)
Test-Item 'DC' 'RODC present sur le site LYON' (@($rodc | Where-Object Site -eq 'LYON').Count -ge 1) (($rodc | ForEach-Object { "$($_.Name)/$($_.Site)" }) -join ', ')
$fsmo = @($Forest.SchemaMaster, $Forest.DomainNamingMaster, $Domain.PDCEmulator, $Domain.RIDMaster, $Domain.InfrastructureMaster)
Test-Item 'DC' 'Roles FSMO portes par un DC de Paris' (@($fsmo | Where-Object { $_ -notmatch '^(BAI-)?PAR-DC0' }).Count -eq 0) (($fsmo | ForEach-Object { ($_ -split '\.')[0] } | Sort-Object -Unique) -join ', ')

# --- Sites et services ----------------------------------------------------------------
foreach ($s in 'PARIS', 'LYON') { Test-Item 'Sites' "Site $s" ([bool](Get-ADReplicationSite -Filter "Name -eq '$s'")) }
foreach ($n in '10.10.0.0/16', '10.20.0.0/16', '10.99.0.0/24') {
    $sn = Get-ADReplicationSubnet -Filter "Name -eq '$n'"
    Test-Item 'Sites' "Sous-reseau $n associe" ([bool]$sn -and [bool]$sn.Site) $(if ($sn) { ($sn.Site -split ',')[0] -replace 'CN=' })
}
Test-Item 'Sites' 'Lien LIEN-PARIS-LYON' ([bool](Get-ADReplicationSiteLink -Filter "Name -eq 'LIEN-PARIS-LYON'"))

# --- OU --------------------------------------------------------------------------------
$ouAttendues = @(
    "OU=ADMINISTRATION,$DomainDN", "OU=Comptes-Admin,OU=ADMINISTRATION,$DomainDN", "OU=Comptes-Service,OU=ADMINISTRATION,$DomainDN",
    "OU=Groupes-Admin,OU=ADMINISTRATION,$DomainDN", $RootOU,
    "OU=Globaux,OU=Groupes,$RootOU", "OU=Domaine-Local,OU=Groupes,$RootOU", "OU=Desactives,$RootOU"
)
foreach ($svc in 'Direction', 'Commercial-ADV', 'Technique', 'Informatique') { $ouAttendues += "OU=$svc,OU=Utilisateurs,OU=PARIS,$RootOU" }
foreach ($svc in 'Commercial', 'Technique') { $ouAttendues += "OU=$svc,OU=Utilisateurs,OU=LYON,$RootOU" }
foreach ($site in 'PARIS', 'LYON') { foreach ($o in 'OU=Fixes,OU=Ordinateurs', 'OU=Portables,OU=Ordinateurs', 'OU=Serveurs') { $ouAttendues += "$o,OU=$site,$RootOU" } }
$ouAbsentes = @($ouAttendues | Where-Object { -not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$_'") })
Test-Item 'OU' "$($ouAttendues.Count) OU attendues presentes" ($ouAbsentes.Count -eq 0) ($ouAbsentes -join ' | ')
$nonProtegees = @(Get-ADOrganizationalUnit -SearchBase $RootOU -Filter * -Properties ProtectedFromAccidentalDeletion | Where-Object { -not $_.ProtectedFromAccidentalDeletion })
Test-Item 'OU' 'OU protegees contre la suppression accidentelle' ($nonProtegees.Count -eq 0) (($nonProtegees | ForEach-Object Name) -join ', ')

# --- Utilisateurs ----------------------------------------------------------------------
$users = @(Get-ADUser -SearchBase $RootOU -Filter * -Properties EmployeeID, Department, Title, Office, EmailAddress)
$actifs = @($users | Where-Object { $_.Enabled -and $_.DistinguishedName -notmatch 'OU=Desactives' })
Test-Item 'Comptes' "$NombreUtilisateursAttendu comptes utilisateurs actifs" ($actifs.Count -eq $NombreUtilisateursAttendu) "$($actifs.Count) trouves"
$repartition = $actifs | Group-Object { (($_.DistinguishedName -split ',')[3, 1] -replace '^OU=', '') -join '/' } |
               ForEach-Object { "$($_.Name)=$($_.Count)" }
Test-Item 'Comptes' 'Repartition par site / service' $true ($repartition -join ' ; ')
$badSam = @($actifs | Where-Object { $_.SamAccountName -cnotmatch '^[a-z-]+\.[a-z-]+[0-9]?$' -or $_.SamAccountName.Length -gt 20 })
Test-Item 'Nommage' 'Logins au format prenom.nom (minuscules, <= 20 car.)' ($badSam.Count -eq 0) (($badSam | ForEach-Object SamAccountName) -join ', ')
$badUpn = @($actifs | Where-Object { $_.UserPrincipalName -ne "$($_.SamAccountName)@$UpnSuffix" })
Test-Item 'Nommage' "UPN = login@$UpnSuffix" ($badUpn.Count -eq 0) (($badUpn | ForEach-Object SamAccountName) -join ', ')
$incomplets = @($actifs | Where-Object { -not $_.EmployeeID -or -not $_.Department -or -not $_.Title -or -not $_.Office })
Test-Item 'Comptes' 'Attributs renseignes (matricule, service, fonction, site)' ($incomplets.Count -eq 0) (($incomplets | ForEach-Object SamAccountName) -join ', ')
$doublons = @($actifs | Group-Object EmployeeID | Where-Object Count -gt 1)
Test-Item 'Comptes' 'Matricules (employeeID) uniques' ($doublons.Count -eq 0)

# --- Groupes ---------------------------------------------------------------------------
$gg = @(Get-ADGroup -SearchBase "OU=Globaux,OU=Groupes,$RootOU" -Filter *)
$dl = @(Get-ADGroup -SearchBase "OU=Domaine-Local,OU=Groupes,$RootOU" -Filter *)
Test-Item 'Groupes' 'Groupes GG_ : portee Globale et prefixe respecte' (@($gg | Where-Object { $_.GroupScope -ne 'Global' -or $_.Name -notlike 'GG_*' }).Count -eq 0) "$($gg.Count) groupes"
Test-Item 'Groupes' 'Groupes DL_ : portee Domaine local et prefixe respecte' (@($dl | Where-Object { $_.GroupScope -ne 'DomainLocal' -or $_.Name -notlike 'DL_*' }).Count -eq 0) "$($dl.Count) groupes"
$dlAvecUsers = @($dl | Where-Object { @(Get-ADGroupMember $_ | Where-Object objectClass -eq 'user').Count -gt 0 })
Test-Item 'Groupes' 'AGDLP : aucun utilisateur directement dans un DL_' ($dlAvecUsers.Count -eq 0) (($dlAvecUsers | ForEach-Object Name) -join ', ')
foreach ($g in 'GG_PAR_Utilisateurs', 'GG_LYS_Utilisateurs', 'GG_FM_Nomades') {
    $c = @(Get-ADGroupMember -Identity $g -ErrorAction SilentlyContinue).Count
    Test-Item 'Groupes' "Membres de $g" ($c -gt 0) "$c membres"
}
$sansGroupe = @($actifs | Where-Object { @(Get-ADPrincipalGroupMembership $_ | Where-Object Name -like 'GG_*').Count -lt 2 })
Test-Item 'Groupes' 'Chaque utilisateur est dans son GG de site et de service' ($sansGroupe.Count -eq 0) (($sansGroupe | ForEach-Object SamAccountName) -join ', ')

# --- Comptes a privileges et de service -----------------------------------------------
Test-Item 'Securite' 'Compte svc-glpi dans ADMINISTRATION\Comptes-Service' ([bool](Get-ADUser -Filter "SamAccountName -eq 'svc-glpi'" -SearchBase "OU=Comptes-Service,OU=ADMINISTRATION,$DomainDN"))
$admUsers = @(Get-ADGroupMember 'Admins du domaine' -ErrorAction SilentlyContinue)
if (-not $admUsers) { $admUsers = @(Get-ADGroupMember 'Domain Admins' -ErrorAction SilentlyContinue) }
$admMetier = @($admUsers | Where-Object { $_.distinguishedName -like "*$RootOU" })
Test-Item 'Securite' 'Aucun compte bureautique membre de Admins du domaine' ($admMetier.Count -eq 0) (($admMetier | ForEach-Object SamAccountName) -join ', ')
$rb = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'"
Test-Item 'Securite' 'Corbeille AD activee' ($rb.EnabledScopes.Count -gt 0)

# --- Resultat --------------------------------------------------------------------------
$Results | Format-Table -AutoSize -Wrap
$ko = @($Results | Where-Object Resultat -eq 'KO')
$color = if ($ko.Count -eq 0) { 'Green' } else { 'Red' }
Write-Host ("Bilan : {0} controles, {1} OK, {2} KO" -f $Results.Count, ($Results.Count - $ko.Count), $ko.Count) -ForegroundColor $color
Write-Host 'Completer par : dcdiag /e /q   et   repadmin /replsummary' -ForegroundColor DarkGray
