# =====================================================================
#  Free-Motions - Lot 3 - Deploiement des postes (WDS + WinPE)
#  Etape 2b : compte de service de jonction au domaine
#  A executer sur PAR-DC01, en dom-icoulibaly, PowerShell administrateur
#  LIGNE PAR LIGNE (copier une ligne dans le Bloc-notes, clic droit dans PowerShell)
#
#  Principe : un seul compte de service, avec un seul droit :
#  creer / joindre des ordinateurs dans OU=Ordinateurs,OU=PARIS (Fixes + Portables).
#  Le partage de deploiement n'utilise PAS de compte de service : le technicien
#  s'authentifie avec son propre compte (par-xxx) au demarrage de WinPE.
# =====================================================================

# --- 0. Variables
$dom   = 'DC=free-motions-eq1,DC=com'
$ouSvc = "OU=Comptes-Service,OU=ADMINISTRATION,$dom"
$ouPC  = "OU=Ordinateurs,OU=PARIS,OU=FREE-MOTIONS,$dom"

# --- 1. Mot de passe du compte (long et complexe, a noter : il ira dans unattend.xml SUR LE SERVEUR uniquement)
$pass = Read-Host 'Mot de passe de svc-deploy-join' -AsSecureString

# --- 2. Creation du compte
New-ADUser -Name 'svc-deploy-join' -SamAccountName 'svc-deploy-join' -UserPrincipalName 'svc-deploy-join@free-motions-eq1.com' -Path $ouSvc -AccountPassword $pass -Enabled $true -PasswordNeverExpires $true -CannotChangePassword $true -Description 'Deploiement : jonction des postes au domaine (OU PARIS\Ordinateurs uniquement)'

# --- 3. Delegation sur OU=Ordinateurs,OU=PARIS (et ses sous-OU Fixes / Portables)
#   CC;computer   = creer des comptes ordinateurs
#   GA;;computer  = controle total sur les comptes ordinateurs de l'OU (necessaire pour finaliser la jonction)
dsacls $ouPC /I:T /G 'FREEMOTIONS\svc-deploy-join:CC;computer'
dsacls $ouPC /I:S /G 'FREEMOTIONS\svc-deploy-join:GA;;computer'

# --- 4. Verifications
Get-ADUser -Identity 'svc-deploy-join' -Properties Description, PasswordNeverExpires | Select Name, Enabled, PasswordNeverExpires, Description
(Get-Acl "AD:$ouPC").Access | Where-Object IdentityReference -like '*svc-deploy-join' | Select IdentityReference, ActiveDirectoryRights, InheritanceType
