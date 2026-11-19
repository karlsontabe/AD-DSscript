# =====================================================================
#  Free-Motions - Lot 3 - Etape 5a : creation d'UN compte a la main
#  Exemple : FM0001 - Aminata DIOP - Directrice generale (Paris, Direction, nomade)
#  But : comprendre chaque parametre avant de laisser le script creer les 49 autres.
#  A executer DANS L'ORDRE, bloc par bloc.
# =====================================================================

# --- 0. Variable : racine du domaine
$dom = 'DC=free-motions-eq1,DC=com'

# --- 1. Mot de passe initial : PowerShell le demande sans l'afficher (saisie masquee)
#        Il doit respecter la complexite du domaine : majuscule, minuscule, chiffre, caractere special
$pass = Read-Host 'Mot de passe initial' -AsSecureString

# --- 2. Les parametres du compte, ranges dans un tableau (on appelle ca le "splatting")
#        Coller le bloc ENTIER, de $params jusqu'a l'accolade fermante }
$params = @{
    Name                  = 'Aminata DIOP'                         # nom de l'objet dans la console AD
    GivenName             = 'Aminata'                              # prenom
    Surname               = 'Diop'                                 # nom de famille
    DisplayName           = 'Aminata DIOP'                         # nom affiche (convention : Prenom NOM)
    SamAccountName        = 'aminata.diop'                         # identifiant de connexion (FREEMOTIONS\aminata.diop)
    UserPrincipalName     = 'aminata.diop@free-motions-eq1.com'    # identifiant format mail (UPN)
    EmailAddress          = 'aminata.diop@free-motions-eq1.com'    # adresse de messagerie
    EmployeeID            = 'FM0001'                               # matricule : cle unique du compte
    Title                 = 'Directrice generale'                  # fonction
    Department            = 'Direction'                            # service
    Office                = 'PARIS'                                # site
    Company               = 'Free-Motions'                         # societe
    Path                  = "OU=Direction,OU=Utilisateurs,OU=PARIS,OU=FREE-MOTIONS,$dom"   # OU de destination
    AccountPassword       = $pass                                  # mot de passe saisi a l'etape 1
    Enabled               = $true                                  # compte actif des sa creation
    ChangePasswordAtLogon = $true                                  # changement impose a la 1re connexion
}

# --- 3. Creation du compte : le @ devant params "deplie" le tableau en parametres
New-ADUser @params

# --- 4. Appartenance aux groupes globaux : son site, son service, et nomade (elle a un portable)
Add-ADGroupMember -Identity 'GG_PAR_Utilisateurs' -Members 'aminata.diop'
Add-ADGroupMember -Identity 'GG_PAR_Direction' -Members 'aminata.diop'
Add-ADGroupMember -Identity 'GG_FM_Nomades' -Members 'aminata.diop'

# --- 5. Verification
#        a) le compte et ses attributs
Get-ADUser -Identity 'aminata.diop' -Properties EmployeeID, Title, Department, Office | Select Name, SamAccountName, UserPrincipalName, EmployeeID, Title, Department, Office, Enabled, DistinguishedName
#        b) ses groupes (directs)
Get-ADPrincipalGroupMembership -Identity 'aminata.diop' | Select Name
#        c) AGDLP en action : TOUS les groupes dont elle beneficie, imbrications comprises
#           (la regle LDAP 1.2.840.113556.1.4.1941 suit les groupes imbriques : GG -> DL)
$u = Get-ADUser -Identity 'aminata.diop'
Get-ADGroup -LDAPFilter "(member:1.2.840.113556.1.4.1941:=$($u.DistinguishedName))" | Select Name | Sort Name
