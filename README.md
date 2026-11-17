# Lab Active Directory — Windows Server

Laboratoire Windows Server : domaine Active Directory avec DNS et DHCP, GPO de restriction liées aux unités d'organisation, création d'utilisateurs en masse depuis un CSV en PowerShell.

![Windows Server](https://img.shields.io/badge/Windows%20Server-2022-0078D6?logo=windows&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-5391FE?logo=powershell&logoColor=white)
![Active Directory](https://img.shields.io/badge/Active%20Directory-AD%20DS-blue)

## Objectifs

- Déployer un contrôleur de domaine (nouvelle forêt `lab.local`) avec DNS intégré à AD.
- Distribuer automatiquement les adresses IP des postes clients via DHCP.
- Structurer l'annuaire en unités d'organisation par service.
- Créer des comptes en masse à partir d'un fichier CSV, sans saisie manuelle.
- Restreindre les postes des utilisateurs avec des GPO, avec une exception pour le service informatique.
- Tout automatiser en PowerShell, de façon rejouable (scripts idempotents).

## Architecture

```
                 Réseau LAN 192.168.10.0/24
   ┌──────────────────────────┐         ┌──────────────────────────┐
   │ SRV-DC01                 │         │ Poste client Windows     │
   │ Windows Server 2022      │◄───────►│ Windows 10/11            │
   │ 192.168.10.10 (statique) │         │ IP via DHCP              │
   │ AD DS · DNS · DHCP       │         │ joint au domaine lab.local│
   └──────────────────────────┘         └──────────────────────────┘
```

| Élément | Valeur |
|---|---|
| Domaine / NetBIOS | `lab.local` / `LAB` |
| Contrôleur de domaine | `SRV-DC01` — `192.168.10.10/24`, passerelle `192.168.10.1` |
| DNS | Zone directe `lab.local` + zone inverse `10.168.192.in-addr.arpa` (intégrées AD), redirecteurs `1.1.1.1`, `8.8.8.8` |
| DHCP | Étendue `192.168.10.100 – 200`, exclusion `.100 – .109`, bail 8 jours, options 003/006/015 |

### Arborescence Active Directory

```
lab.local
└── LAB
    ├── Utilisateurs                ← GPO_Restrictions_Utilisateurs, GPO_Fond_Ecran_Entreprise
    │   ├── Comptabilite
    │   ├── RH
    │   ├── Informatique            ← GPO_Exception_Informatique (lève les restrictions)
    │   ├── Direction
    │   └── Commercial
    ├── Ordinateurs                 ← conteneur par défaut des nouveaux postes (redircmp)
    └── Groupes                     ← GG_Comptabilite, GG_RH, GG_Informatique, ...
```

## GPO

| GPO | Liée à | Paramètres |
|---|---|---|
| `GPO_Restrictions_Utilisateurs` | `OU=Utilisateurs` | Panneau de configuration interdit · outils Registre interdits · invite de commandes interdite · stockage USB interdit |
| `GPO_Exception_Informatique` | `OU=Informatique` | Ré-autorise Panneau de configuration, Registre et invite de commandes |
| `GPO_Fond_Ecran_Entreprise` | `OU=Utilisateurs` | Fond d'écran imposé depuis `\\lab.local\NETLOGON` |

La GPO d'exception est liée à l'OU la plus proche des comptes du service informatique : elle s'applique en dernier (ordre **LSDOU**) et l'emporte donc sur la GPO de restriction héritée.

## Contenu du dépôt

```
├── scripts/
│   ├── 01-Install-ADDS.ps1      IP statique, renommage, installation AD DS + création de la forêt
│   ├── 02-Configure-DNS.ps1     Zone inverse, PTR du DC, redirecteurs
│   ├── 03-Configure-DHCP.ps1    Rôle DHCP, autorisation AD, étendue, options, exclusions
│   ├── 04-Create-OUs.ps1        OU par service + groupes globaux GG_<Service>
│   ├── 05-Import-Users.ps1      Création des comptes depuis le CSV
│   ├── 06-Configure-GPO.ps1     Création et liaison des GPO
│   └── 07-Verification.ps1      Contrôle de l'état du lab
├── data/
│   └── utilisateurs.csv         Jeu de données fictif (10 utilisateurs, 5 services)
└── docs/
    ├── verification.md          Tests côté serveur et côté client
    └── captures/                Captures d'écran du lab
```

## Déploiement

Sur un Windows Server 2022 fraîchement installé, dans une console PowerShell **administrateur** :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
cd .\scripts

.\01-Install-ADDS.ps1 -Etape Preparation     # redémarre le serveur
.\01-Install-ADDS.ps1 -Etape Promotion       # crée la forêt, redémarre le serveur

.\02-Configure-DNS.ps1
.\03-Configure-DHCP.ps1
.\04-Create-OUs.ps1
.\05-Import-Users.ps1 -CheminCsv ..\data\utilisateurs.csv -WhatIf   # simulation
.\05-Import-Users.ps1 -CheminCsv ..\data\utilisateurs.csv
.\06-Configure-GPO.ps1
.\07-Verification.ps1
```

Toutes les valeurs (nom de domaine, adresses, étendue, OU…) sont des paramètres des scripts et peuvent être adaptées, par exemple :
`.\03-Configure-DHCP.ps1 -Debut 192.168.10.50 -Fin 192.168.10.150`.

## Import des utilisateurs

Format du CSV (séparateur `;`, UTF-8) :

```csv
Prenom;Nom;Service;Fonction;Telephone
Alice;Martin;Comptabilite;Comptable;0102030401
```

Le script `05-Import-Users.ps1` :
- génère l'identifiant `prenom.nom` (accents retirés, 20 caractères max) et ajoute un suffixe numérique en cas d'homonyme ;
- place le compte dans l'OU de son service et l'ajoute au groupe `GG_<Service>` ;
- renseigne service, fonction et téléphone ;
- demande le mot de passe initial au lancement (il n'est jamais écrit dans le CSV) et impose son changement à la première connexion ;
- ignore les comptes déjà existants, ce qui permet de relancer le script sans doublon ;
- supporte `-WhatIf` pour une simulation.

## Validation

Voir [docs/verification.md](docs/verification.md) : santé du DC (`dcdiag`), résolution DNS directe/inverse, bail DHCP sur le client, jonction au domaine, et test des restrictions avec un utilisateur standard puis un utilisateur du service informatique (`gpresult /r`).

## Compétences mises en œuvre

Windows Server · Active Directory Domain Services · DNS · DHCP · stratégies de groupe (GPO) · PowerShell (modules `ActiveDirectory`, `GroupPolicy`, `DnsServer`, `DhcpServer`) · automatisation et idempotence · documentation technique.
