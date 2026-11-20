# =====================================================================
#  Free-Motions - Lot 3 - Promotion du 2e controleur de domaine : BAI-PAR-DC02
#  Domaine : free-motions-eq1.com  |  IP : 10.10.40.12/24  |  Site AD : PARIS
#  A executer LIGNE PAR LIGNE, dans l'ordre. Le serveur redemarre 2 fois.
#
#  PREREQUIS (Proxmox) : VM Windows Server 2022, carte reseau sur le bridge
#  nat271e1l1 (LAN Paris), idealement sur un autre noeud que BAI-PAR-DC01.
#  Carte reseau en VirtIO : installer les pilotes (ISO virtio-win) pendant
#  l'installation de Windows, sinon la carte n'apparait pas dans Get-NetAdapter.
#
#  IMPORTANT : A1 a A3 se TAPENT A LA MAIN (le serveur n'a pas encore de reseau).
#  Une fois A4 OK, telecharger ce fichier depuis GitHub pour la suite :
#    New-Item -ItemType Directory -Path C:\Scripts
#    $git = 'https://raw.githubusercontent.com/karlsontabe/AD-DSscript/main'
#    Invoke-WebRequest "$git/dc02.ps1" -OutFile C:\Scripts\dc02.ps1 -UseBasicParsing
#    notepad C:\Scripts\dc02.ps1
# =====================================================================


# ===================== PARTIE A - sur DC02 (avant redemarrage) =====================

# --- A1. Reperer la carte reseau : noter la valeur ifIndex
Get-NetAdapter

# --- A2. IP fixe (remplacer 4 par le ifIndex vu en A1). Passerelle = FW-PAR01
New-NetIPAddress -InterfaceIndex 4 -IPAddress 10.10.40.12 -PrefixLength 24 -DefaultGateway 10.10.40.254

# --- A3. DNS = BAI-PAR-DC01 (indispensable : c'est lui qui connait le domaine)
Set-DnsClientServerAddress -InterfaceIndex 4 -ServerAddresses 10.10.40.11

# --- A4. Tests : DC01 repond et le domaine est resolu (on attend 10.10.40.11)
Test-Connection 10.10.40.11 -Count 2
nslookup free-motions-eq1.com

# --- A5. Heure : doit etre a moins de 5 min de DC01 (sinon Kerberos refuse la promotion)
Get-Date
#        Si l'heure est fausse, se caler sur DC01 :
w32tm /config /manualpeerlist:10.10.40.11 /syncfromflags:manual /update
Restart-Service w32time
w32tm /resync /force

# --- A6. Renommer selon la convention puis redemarrer (AVANT la promotion)
Rename-Computer -NewName 'BAI-PAR-DC02' -Restart


# ===================== PARTIE B - sur DC02 (apres le 1er redemarrage) =====================

# --- B1. Verifier le nom
hostname

# --- B2. Installer le role AD DS + les outils d'administration
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# --- B3. Identifiants d'un admin du domaine (format : FREEMOTIONS\Administrateur)
$cred = Get-Credential

# --- B4. Mot de passe DSRM : mode restauration des services d'annuaire (a noter et conserver !)
$dsrm = Read-Host 'Mot de passe DSRM' -AsSecureString

# --- B5. Promotion en DC supplementaire du domaine existant
#        -InstallDns : DC02 heberge aussi le DNS (redondance DNS)
#        -SiteName PARIS : place dans le bon site AD
#        Le catalogue global est installe par defaut. Le serveur redemarre tout seul a la fin.
Install-ADDSDomainController -DomainName 'free-motions-eq1.com' -Credential $cred -SafeModeAdministratorPassword $dsrm -InstallDns -SiteName 'PARIS' -Force


# ===================== PARTIE C - verifications (sur DC01 ou DC02, apres le 2e redemarrage) =====================

# --- C1. Les deux DC, leur site, catalogue global (on attend 2 lignes, PARIS, True)
Get-ADDomainController -Filter * | Select Name, IPv4Address, Site, IsGlobalCatalog, IsReadOnly

# --- C2. Replication : 0 echec dans les deux sens
repadmin /replsummary

# --- C3. Sante des DC : aucune sortie = aucune erreur
dcdiag /e /q

# --- C4. Preuve que la replication a tout copie : DC02 connait les 50 comptes
(Get-ADUser -Filter * -SearchBase 'OU=FREE-MOTIONS,DC=free-motions-eq1,DC=com' -Server BAI-PAR-DC02).Count

# --- C5. Heure de DC02 : maintenant qu'il est DC, il doit suivre la hierarchie du domaine
#         (il se cale sur le PDC BAI-PAR-DC01, qui lui se cale sur fr.pool.ntp.org)
#         A executer SUR DC02 : annule le reglage manuel fait en A5
w32tm /config /syncfromflags:domhier /update
Restart-Service w32time
w32tm /resync
w32tm /query /source
#         On attend : BAI-PAR-DC01.free-motions-eq1.com


# ===================== PARTIE D - DNS croise (redondance) =====================
# Bonne pratique : chaque DC interroge d'abord l'AUTRE DC, puis lui-meme.

# --- D1. Sur DC02 (remplacer 4 par son ifIndex)
Set-DnsClientServerAddress -InterfaceIndex 4 -ServerAddresses 10.10.40.11,127.0.0.1

# --- D2. Sur DC01 (verifier son ifIndex avec Get-NetAdapter)
Set-DnsClientServerAddress -InterfaceIndex 4 -ServerAddresses 10.10.40.12,127.0.0.1


# ===================== PARTIE E - recette finale (sur DC01) =====================
# Les 2 KO deviennent 1 seul : "RODC present sur le site LYON" (LYS-RODC01 pas encore deploye)
cd C:\Scripts
.\test.ps1
