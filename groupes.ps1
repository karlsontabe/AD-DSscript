# =====================================================================
#  Free-Motions - Lot 3 - Etape 4 : groupes de securite (modele AGDLP)
#  Domaine : free-motions-eq1.com
#  A executer LIGNE PAR LIGNE (copier une ligne, clic droit dans PowerShell)
#
#  AGDLP : les comptes (A) vont dans des groupes Globaux (G = les personnes,
#  par site/service), qui vont dans des groupes de Domaine Local (DL = un droit
#  sur une ressource). Seuls les DL recoivent des Permissions (P).
# =====================================================================

# --- 0. Variables : racine du domaine et OU de destination des groupes
$dom = 'DC=free-motions-eq1,DC=com'
$gg  = "OU=Globaux,OU=Groupes,OU=FREE-MOTIONS,$dom"
$dl  = "OU=Domaine-Local,OU=Groupes,OU=FREE-MOTIONS,$dom"
$adm = "OU=Groupes-Admin,OU=ADMINISTRATION,$dom"

# --- 1. Groupes GLOBAUX de PARIS : tout le site + un par service
New-ADGroup -Name 'GG_PAR_Utilisateurs' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Tous les utilisateurs du site PARIS'
New-ADGroup -Name 'GG_PAR_Direction' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Service Direction - PARIS'
New-ADGroup -Name 'GG_PAR_Commercial-ADV' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Service Commercial-ADV - PARIS'
New-ADGroup -Name 'GG_PAR_Technique' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Service Technique - PARIS'
New-ADGroup -Name 'GG_PAR_Informatique' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Service Informatique - PARIS'

# --- 2. Groupes GLOBAUX de LYON
New-ADGroup -Name 'GG_LYS_Utilisateurs' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Tous les utilisateurs du site LYON (mise en cache sur le RODC)'
New-ADGroup -Name 'GG_LYS_Commercial' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Service Commercial - LYON'
New-ADGroup -Name 'GG_LYS_Technique' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Service Technique - LYON'
New-ADGroup -Name 'GG_LYS_Ordinateurs' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Postes de Lyon - mise en cache autorisee sur LYS-RODC01'

# --- 3. Groupes GLOBAUX transverses
New-ADGroup -Name 'GG_FM_Nomades' -GroupScope Global -GroupCategory Security -Path $gg -Description 'Utilisateurs equipes d un portable - acces VPN nomades'
New-ADGroup -Name 'GG_ADM_Infra' -GroupScope Global -GroupCategory Security -Path $adm -Description 'Administrateurs de l infrastructure (comptes adm-)'

# --- 4. Groupes de DOMAINE LOCAL : un groupe = un droit sur une ressource
#        Suffixe _RW = modification, _RO = lecture seule
New-ADGroup -Name 'DL_FS_Direction_RW' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'PAR-FS01 \Direction - modification'
New-ADGroup -Name 'DL_FS_Commercial_RW' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'PAR-FS01 \Commercial - modification'
New-ADGroup -Name 'DL_FS_Commercial_RO' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'PAR-FS01 \Commercial - lecture'
New-ADGroup -Name 'DL_FS_Technique_RW' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'PAR-FS01 \Technique - modification'
New-ADGroup -Name 'DL_FS_Technique_RO' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'PAR-FS01 \Technique - lecture'
New-ADGroup -Name 'DL_FS_Informatique_RW' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'PAR-FS01 \Informatique - modification'
New-ADGroup -Name 'DL_FS_Commun_RW' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'PAR-FS01 \Commun - modification (tous)'
New-ADGroup -Name 'DL_RDS_Utilisateurs' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'PAR-RDS01 - ouverture de session RDS'
New-ADGroup -Name 'DL_VPN_Nomades' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'FW-PAR01 - authentification VPN nomades'
New-ADGroup -Name 'DL_GLPI_Utilisateurs' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'SRV-GLPI - import LDAP (profil Self-Service)'
New-ADGroup -Name 'DL_GLPI_Techniciens' -GroupScope DomainLocal -GroupCategory Security -Path $dl -Description 'SRV-GLPI - import LDAP (profil Technicien)'

# --- 5. Imbrication AGDLP : on met les GG (les personnes) DANS les DL (les droits)
#        Lecture : "les membres de GG_x recoivent le droit DL_y"
Add-ADGroupMember -Identity 'DL_FS_Direction_RW' -Members 'GG_PAR_Direction'
Add-ADGroupMember -Identity 'DL_FS_Commercial_RW' -Members 'GG_PAR_Commercial-ADV','GG_LYS_Commercial'
Add-ADGroupMember -Identity 'DL_FS_Commercial_RO' -Members 'GG_PAR_Direction'
Add-ADGroupMember -Identity 'DL_FS_Technique_RW' -Members 'GG_PAR_Technique','GG_LYS_Technique'
Add-ADGroupMember -Identity 'DL_FS_Technique_RO' -Members 'GG_PAR_Commercial-ADV','GG_LYS_Commercial'
Add-ADGroupMember -Identity 'DL_FS_Informatique_RW' -Members 'GG_PAR_Informatique'
Add-ADGroupMember -Identity 'DL_FS_Commun_RW' -Members 'GG_PAR_Utilisateurs','GG_LYS_Utilisateurs'
Add-ADGroupMember -Identity 'DL_RDS_Utilisateurs' -Members 'GG_PAR_Utilisateurs','GG_LYS_Utilisateurs'
Add-ADGroupMember -Identity 'DL_VPN_Nomades' -Members 'GG_FM_Nomades'
Add-ADGroupMember -Identity 'DL_GLPI_Utilisateurs' -Members 'GG_PAR_Utilisateurs','GG_LYS_Utilisateurs'
Add-ADGroupMember -Identity 'DL_GLPI_Techniciens' -Members 'GG_PAR_Informatique'

# --- 6. Verification
#        a) les 22 groupes avec leur portee (11 Global + 11 DomainLocal)
Get-ADGroup -Filter "Name -like 'GG_*' -or Name -like 'DL_*'" | Select Name, GroupScope | Sort Name
(Get-ADGroup -Filter "Name -like 'GG_*' -or Name -like 'DL_*'").Count
#        b) exemple d'imbrication : qui a le droit de modifier le dossier Commercial ?
Get-ADGroupMember -Identity 'DL_FS_Commercial_RW' | Select Name
