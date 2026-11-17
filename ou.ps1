# =====================================================================
#  Free-Motions - Lot 3 - Etape 3 : arborescence des OU
#  Domaine : free-motions-eq1.com
#  A executer LIGNE PAR LIGNE (copier une ligne, clic droit dans PowerShell)
#  Regle : toujours creer le PARENT avant l'ENFANT.
# =====================================================================

# --- 0. Variable : racine du domaine (a relancer si tu fermes PowerShell)
$dom = 'DC=free-motions-eq1,DC=com'

# --- 1. Les deux racines : administration separee de l'entreprise
New-ADOrganizationalUnit -Name 'ADMINISTRATION' -Path $dom
New-ADOrganizationalUnit -Name 'FREE-MOTIONS' -Path $dom

# --- 2. Contenu d'ADMINISTRATION (comptes adm-, comptes svc-, groupes admin)
New-ADOrganizationalUnit -Name 'Comptes-Admin' -Path "OU=ADMINISTRATION,$dom"
New-ADOrganizationalUnit -Name 'Comptes-Service' -Path "OU=ADMINISTRATION,$dom"
New-ADOrganizationalUnit -Name 'Groupes-Admin' -Path "OU=ADMINISTRATION,$dom"

# --- 3. Deuxieme niveau de FREE-MOTIONS : un niveau par site + groupes + desactives
New-ADOrganizationalUnit -Name 'PARIS' -Path "OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'LYON' -Path "OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Groupes' -Path "OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Desactives' -Path "OU=FREE-MOTIONS,$dom"

# --- 4. PARIS : par type d'objet
New-ADOrganizationalUnit -Name 'Utilisateurs' -Path "OU=PARIS,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Ordinateurs' -Path "OU=PARIS,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Serveurs' -Path "OU=PARIS,OU=FREE-MOTIONS,$dom"

# --- 5. PARIS\Utilisateurs : un OU par service (40 comptes)
New-ADOrganizationalUnit -Name 'Direction' -Path "OU=Utilisateurs,OU=PARIS,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Commercial-ADV' -Path "OU=Utilisateurs,OU=PARIS,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Technique' -Path "OU=Utilisateurs,OU=PARIS,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Informatique' -Path "OU=Utilisateurs,OU=PARIS,OU=FREE-MOTIONS,$dom"

# --- 6. PARIS\Ordinateurs : postes fixes / portables (GPO differentes : BitLocker, VPN)
New-ADOrganizationalUnit -Name 'Fixes' -Path "OU=Ordinateurs,OU=PARIS,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Portables' -Path "OU=Ordinateurs,OU=PARIS,OU=FREE-MOTIONS,$dom"

# --- 7. LYON : par type d'objet
New-ADOrganizationalUnit -Name 'Utilisateurs' -Path "OU=LYON,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Ordinateurs' -Path "OU=LYON,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Serveurs' -Path "OU=LYON,OU=FREE-MOTIONS,$dom"

# --- 8. LYON\Utilisateurs : un OU par service (10 comptes)
New-ADOrganizationalUnit -Name 'Commercial' -Path "OU=Utilisateurs,OU=LYON,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Technique' -Path "OU=Utilisateurs,OU=LYON,OU=FREE-MOTIONS,$dom"

# --- 9. LYON\Ordinateurs
New-ADOrganizationalUnit -Name 'Fixes' -Path "OU=Ordinateurs,OU=LYON,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Portables' -Path "OU=Ordinateurs,OU=LYON,OU=FREE-MOTIONS,$dom"

# --- 10. Groupes : GG_ (globaux = les personnes) et DL_ (domaine local = les droits)
New-ADOrganizationalUnit -Name 'Globaux' -Path "OU=Groupes,OU=FREE-MOTIONS,$dom"
New-ADOrganizationalUnit -Name 'Domaine-Local' -Path "OU=Groupes,OU=FREE-MOTIONS,$dom"

# --- 11. Verification : 27 OU creees + Domain Controllers = 28 au total
Get-ADOrganizationalUnit -Filter * | Select DistinguishedName | Sort DistinguishedName
(Get-ADOrganizationalUnit -Filter *).Count
