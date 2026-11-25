# Free-Motions - Deploiement automatise des postes (WDS + WinPE)

Lot 3 - carte « Deploiement automatise des postes ». Equipe ANSK.

## Principe
- **WDS** (PAR-WDS01, 10.10.40.71) sert uniquement au demarrage PXE.
- Un **WinPE personnalise** (fabrique avec l'ADK) demande le compte du technicien,
  se connecte a `\\PAR-WDS01\Deploy$` et affiche un menu : deployer / capturer.
- **Capture** : DISM capture un Windows 11 de reference generalise (sysprep) -> `Images\W11-REF.wim`.
- **Deploiement** : partitionnement UEFI, DISM applique l'image, `unattend.xml` nomme le poste
  et le joint au domaine dans `OU=Fixes|Portables,OU=Ordinateurs,OU=PARIS`.
- `SetupComplete.cmd` supprime le fichier de reponse (mots de passe) a la fin de l'installation.

Pourquoi pas MDT ni « Windows Setup en mode WDS » : MDT est retire et n'est plus telechargeable ;
le boot.wim d'installation de Windows 11 est bloque en mode WDS. Le PXE avec image de demarrage
personnalisee reste supporte.

## Fichiers
| Fichier | Ou | Role |
|---|---|---|
| `2b-comptes-service.ps1` | PAR-DC01 (dom-) | Compte `svc-deploy-join` + delegation sur l'OU des ordinateurs de Paris |
| `recuperer-fichiers.ps1` | PAR-WDS01 | Telecharge tous les fichiers ci-dessous dans `F:\Deploy` |
| `build-winpe.cmd` | PAR-WDS01 | Fabrique `F:\WinPE\media\sources\boot.wim` |
| `startnet.cmd` | dans WinPE | Initialise WinPE, connecte le partage avec le compte du technicien |
| `menu.cmd` | `Deploy$\Scripts` | Menu deployer / capturer |
| `deploy.cmd` + `uefi.txt` | `Deploy$\Scripts` | Deploiement de l'image |
| `capture.cmd` | `Deploy$\Scripts` | Capture de l'image de reference |
| `SetupComplete.cmd` | copie sur le poste | Nettoyage des fichiers de reponse |
| `unattend.xml` | `Deploy$\Unattend` | Modele sans mot de passe (placeholders a remplacer sur le serveur) |

## Securite
- Aucun mot de passe sur ce depot public : `unattend.xml` contient des placeholders.
- Aucun mot de passe dans l'image de demarrage : le technicien s'authentifie.
- `svc-deploy-join` ne peut que creer/joindre des ordinateurs dans l'OU des postes de Paris.
