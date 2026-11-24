# =====================================================================
#  Free-Motions - Lot 3 - Comptes d'administration par perimetre
#  et desactivation du compte Administrateur integre
#  A executer sur PAR-DC01, bloc par bloc, DANS L'ORDRE.
#
#  Comptes NOMINATIFS du service informatique de Free-Motions (le client),
#  un compte par personne ET par perimetre. Convention : <perimetre>-<initiale><nom>
#   dom- : domaine (Admins du domaine)             -> GG_ADM_Infra
#   par- : site de Paris (OU PARIS)                -> GG_ADM_Paris
#   lys- : site de Lyon (OU LYON + RODC)           -> GG_ADM_Lyon
#   fs-  : serveurs de fichiers (PAR-FS01)         -> GG_ADM_FS
#  Principe : on donne les droits aux GROUPES, et on met les comptes dans les groupes.
#  Ces comptes sont distincts des comptes bureautiques (ibrahim.coulibaly, amelie.caron).
# =====================================================================

# --- 0. Variables
$dom   = 'DC=free-motions-eq1,DC=com'
$ouAdm = "OU=Comptes-Admin,OU=ADMINISTRATION,$dom"
$ouGrp = "OU=Groupes-Admin,OU=ADMINISTRATION,$dom"
$ouPar = "OU=PARIS,OU=FREE-MOTIONS,$dom"
$ouLys = "OU=LYON,OU=FREE-MOTIONS,$dom"
$sid   = (Get-ADDomain).DomainSID.Value
#        SID fixes : -512 = Admins du domaine, -500 = Administrateur integre (independant de la langue)
$da    = Get-ADGroup -Identity "$sid-512"
$da.Name


# ===================== 1. GROUPES D'ADMINISTRATION =====================
#        GG_ADM_Infra existe deja (cree avec groupes.ps1)
Set-ADGroup -Identity 'GG_ADM_Infra' -Description 'Administration du domaine (Admins du domaine)'
New-ADGroup -Name 'GG_ADM_Paris' -GroupScope Global -GroupCategory Security -Path $ouGrp -Description 'Administration du site de Paris (OU PARIS)'
New-ADGroup -Name 'GG_ADM_Lyon' -GroupScope Global -GroupCategory Security -Path $ouGrp -Description 'Administration du site de Lyon (OU LYON + RODC)'
New-ADGroup -Name 'GG_ADM_FS' -GroupScope Global -GroupCategory Security -Path $ouGrp -Description 'Administration des serveurs de fichiers'

#        GG_ADM_Infra devient membre de Admins du domaine
#        (on gere les personnes dans GG_ADM_Infra, jamais directement dans Admins du domaine)
Add-ADGroupMember -Identity $da -Members 'GG_ADM_Infra'


# ===================== 2. LES 4 COMPTES =====================
# --- 2a. Mot de passe initial (change a la 1re connexion) : 12 caracteres min., complexe
$pass = Read-Host 'Mot de passe initial des comptes admin' -AsSecureString

# --- 2b. Liste des comptes (service informatique de Free-Motions)
#         Ibrahim COULIBALY : responsable informatique  |  Amelie CARON : technicienne support
$admins = @(
    @{ Login = 'dom-icoulibaly'; Prenom = 'Ibrahim'; Nom = 'Coulibaly'; Groupe = 'GG_ADM_Infra'; Desc = 'Domaine - Ibrahim COULIBALY (responsable informatique) - usage exceptionnel' },
    @{ Login = 'par-icoulibaly'; Prenom = 'Ibrahim'; Nom = 'Coulibaly'; Groupe = 'GG_ADM_Paris'; Desc = 'Site de Paris - Ibrahim COULIBALY' },
    @{ Login = 'lys-icoulibaly'; Prenom = 'Ibrahim'; Nom = 'Coulibaly'; Groupe = 'GG_ADM_Lyon';  Desc = 'Site de Lyon (a distance) - Ibrahim COULIBALY' },
    @{ Login = 'fs-icoulibaly';  Prenom = 'Ibrahim'; Nom = 'Coulibaly'; Groupe = 'GG_ADM_FS';    Desc = 'Serveurs de fichiers - Ibrahim COULIBALY' },
    @{ Login = 'par-acaron';     Prenom = 'Amelie';  Nom = 'Caron';     Groupe = 'GG_ADM_Paris'; Desc = 'Site de Paris (support) - Amelie CARON' },
    @{ Login = 'lys-acaron';     Prenom = 'Amelie';  Nom = 'Caron';     Groupe = 'GG_ADM_Lyon';  Desc = 'Site de Lyon (support a distance) - Amelie CARON' }
)

# --- 2c. Creation (meme New-ADUser @params que pour les utilisateurs)
#         -AccountNotDelegated pour le compte du domaine : son identite ne peut pas etre empruntee par un service
foreach ($a in $admins) {
    $perim = $a.Login.Split('-')[0].ToUpper()
    $params = @{
        Name                  = "$($a.Prenom) $($a.Nom.ToUpper()) ($perim)"
        GivenName             = $a.Prenom
        Surname               = $a.Nom
        DisplayName           = "$($a.Prenom) $($a.Nom.ToUpper()) ($perim)"
        SamAccountName        = $a.Login
        UserPrincipalName     = "$($a.Login)@free-motions-eq1.com"
        Description           = $a.Desc
        Path                  = $ouAdm
        AccountPassword       = $pass
        Enabled               = $true
        ChangePasswordAtLogon = $true
        AccountNotDelegated   = ($perim -eq 'DOM')
    }
    New-ADUser @params
    Add-ADGroupMember -Identity $a.Groupe -Members $a.Login
    Write-Host "Cree : $($a.Login) -> $($a.Groupe)" -ForegroundColor Green
}


# ===================== 3. DELEGATION SUR LES OU (Paris / Lyon) =====================
#  dsacls modifie les droits sur un objet de l'annuaire (ici une OU).
#   /I:T = l'OU et tout son contenu    /I:S = uniquement le contenu (pas l'OU elle-meme)
#   CCDC;user     = creer / supprimer des comptes utilisateurs dans l'OU
#   CCDC;computer = creer / supprimer des comptes ordinateurs (jonction de postes)
#   GA;;user      = controle total sur les comptes utilisateurs de l'OU (mot de passe, deverrouillage, attributs)
#   GA;;computer  = controle total sur les comptes ordinateurs de l'OU

# --- 3a. Paris : GG_ADM_Paris gere les comptes et les postes de l'OU PARIS uniquement
dsacls $ouPar /I:T /G 'FREEMOTIONS\GG_ADM_Paris:CCDC;user' 'FREEMOTIONS\GG_ADM_Paris:CCDC;computer'
dsacls $ouPar /I:S /G 'FREEMOTIONS\GG_ADM_Paris:GA;;user' 'FREEMOTIONS\GG_ADM_Paris:GA;;computer'

# --- 3b. Lyon : GG_ADM_Lyon gere les comptes et les postes de l'OU LYON uniquement
dsacls $ouLys /I:T /G 'FREEMOTIONS\GG_ADM_Lyon:CCDC;user' 'FREEMOTIONS\GG_ADM_Lyon:CCDC;computer'
dsacls $ouLys /I:S /G 'FREEMOTIONS\GG_ADM_Lyon:GA;;user' 'FREEMOTIONS\GG_ADM_Lyon:GA;;computer'

# --- 3c. Verification : les delegations apparaissent dans les droits de l'OU
(Get-Acl "AD:$ouPar").Access | Where-Object IdentityReference -like '*GG_ADM_Paris' | Select IdentityReference, ActiveDirectoryRights, InheritanceType
(Get-Acl "AD:$ouLys").Access | Where-Object IdentityReference -like '*GG_ADM_Lyon' | Select IdentityReference, ActiveDirectoryRights, InheritanceType


# ===================== 4. ADMIN LOCAL DE PAR-FS01 POUR GG_ADM_FS =====================
#  Ajoute GG_ADM_FS au groupe local Administrateurs de PAR-FS01, a distance (WinRM).
#  S-1-5-32-544 = Administrateurs (local), quelle que soit la langue.
Invoke-Command -ComputerName PAR-FS01 -ScriptBlock { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'FREEMOTIONS\GG_ADM_FS' }
Invoke-Command -ComputerName PAR-FS01 -ScriptBlock { Get-LocalGroupMember -SID 'S-1-5-32-544' }

#  A transmettre a l'equipe (hors de ce script) :
#   - Arame (RODC Lyon) : a la promotion de LYS-RODC01, ajouter
#       -DelegatedAdministratorAccountName 'FREEMOTIONS\GG_ADM_Lyon'
#     -> lys-icoulibaly et lys-acaron seront admins locaux du RODC SANS aucun droit sur le domaine
#   - Arame (GPO admin local) : GG_ADM_Paris admin local des postes de Paris,
#     GG_ADM_Lyon admin local des postes de Lyon (GPO "Groupes restreints")


# ===================== 5. VERIFICATIONS =====================
Get-ADUser -Filter * -SearchBase $ouAdm -Properties Description | Select SamAccountName, Description, Enabled
#        Qui est REELLEMENT admin du domaine (imbrications comprises) : on attend Administrateur + dom-icoulibaly
Get-ADGroupMember -Identity $da -Recursive | Select SamAccountName


# =====================================================================
#  6. TESTS DE DELEGATION (preuves pour le dossier)
#  Ouvrir un PowerShell sous par-acaron (le mot de passe sera a changer) :
runas /user:FREEMOTIONS\par-acaron powershell
#  Dans cette fenetre par-acaron :
#   - Paris : doit REUSSIR
#       Unlock-ADAccount -Identity 'julien.moreau'
#       Set-ADUser -Identity 'julien.moreau' -Office 'PARIS'
#   - Lyon : doit ECHOUER (acces refuse)
#       Set-ADUser -Identity 'lea.fabre' -Office 'LYON'
#   - Domaine : doit ECHOUER (acces refuse)
#       New-ADGroup -Name 'GG_Test' -GroupScope Global -Path 'OU=Globaux,OU=Groupes,OU=FREE-MOTIONS,DC=free-motions-eq1,DC=com'
# =====================================================================


# =====================================================================
#  7. ETAPE CRITIQUE - NE PAS SAUTER
#  QUAND : a la fin du projet (livraison au client). Tant qu'ANSK travaille sur la maquette,
#  l'equipe a besoin d'un compte domaine ; desactiver Administrateur seulement a la livraison
#  (ou quand toute l'equipe utilise dom-icoulibaly).
#  Avant de desactiver Administrateur, verifier que dom-icoulibaly fonctionne :
runas /user:FREEMOTIONS\dom-icoulibaly powershell
#  Dans cette fenetre : changer le mot de passe demande, puis :
#       whoami /groups | findstr /i "admins"
#  -> la ligne "Admins du domaine" doit apparaitre. Sinon, NE PAS continuer.
# =====================================================================


# ===================== 8. DESACTIVATION DE ADMINISTRATEUR =====================
#  A executer DEPUIS LA FENETRE dom-icoulibaly
$sid    = (Get-ADDomain).DomainSID.Value
$adm500 = Get-ADUser -Identity "$sid-500"
Set-ADUser -Identity $adm500 -Description 'Compte integre DESACTIVE - remplace par les comptes nominatifs par perimetre (dom-, par-, lys-, fs-)'
Disable-ADAccount -Identity $adm500

#  Verification finale : on attend Enabled = False
Get-ADUser -Identity "$sid-500" | Select Name, SID, Enabled
