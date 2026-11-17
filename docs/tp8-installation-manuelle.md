# TP 8.1 — Installation manuelle d'AD DS, DNS et DHCP

Première partie du lab, réalisée **en interface graphique** (Gestionnaire de serveur) sur une machine virtuelle Windows Server, dans le cadre du cours *Serveurs et gestion de l'accès* (DEP Soutien informatique, ESIDEM Montréal).

## Machine virtuelle

| Paramètre | Valeur |
|---|---|
| Nom de la VM | `WIN-SRV-TP8` |
| Mémoire | 4 Go |
| Disque | 50 Go |
| Système | Windows Server 2019/2022 64 bits |

## 1. Nom du serveur

Le serveur est renommé **`Serveur-TP8`** avant toute installation de rôle (le nom d'un contrôleur de domaine ne doit plus changer ensuite).

![Renommage du serveur](captures/tp8/01-nom-serveur.png)

## 2. Adresse IP statique

Un contrôleur de domaine et un serveur DHCP doivent avoir une adresse fixe. Le serveur pointe vers **lui-même** comme DNS, puisqu'il va héberger la zone du domaine.

| IP | Masque | Passerelle | DNS |
|---|---|---|---|
| `192.168.1.20` | `255.255.255.0` | `192.168.1.1` | `192.168.1.20` |

![Configuration IPv4](captures/tp8/02-ip-statique.png)

## 3. Ajout des rôles

Rôles installés depuis *Gérer → Ajouter des rôles et fonctionnalités* : **AD DS**, **DHCP** et **DNS**.

![Rôles installés](captures/tp8/03-roles-adds-dhcp-dns.png)

## 4. Promotion en contrôleur de domaine

Assistant de configuration AD DS → **Ajouter une nouvelle forêt**, domaine racine **`Esidem.ca`**.

![Nouvelle forêt Esidem.ca](captures/tp8/04-nouvelle-foret.png)

## 5. Étendue DHCP

Après la promotion, le serveur DHCP est autorisé dans Active Directory, puis une étendue IPv4 est créée pour distribuer les adresses **`192.168.1.60` à `192.168.1.80`** (/24) aux clients, avec la passerelle et le DNS du domaine. Équivalent PowerShell :

```powershell
Add-DhcpServerInDC -DnsName "Serveur-TP8.Esidem.ca" -IPAddress 192.168.1.20

Add-DhcpServerv4Scope -Name "LAN-TP8" -StartRange 192.168.1.60 -EndRange 192.168.1.80 `
    -SubnetMask 255.255.255.0 -State Active
Set-DhcpServerv4OptionValue -ScopeId 192.168.1.0 -Router 192.168.1.1 `
    -DnsServer 192.168.1.20 -DnsDomain "Esidem.ca"
```

Aucune exclusion n'est nécessaire : le serveur (`.20`) et la passerelle (`.1`) sont en dehors de la plage distribuée.

## 6. Premier utilisateur du domaine

Création du compte **Jane Doe**, nom d'ouverture de session **`jane.doe`** (`jane.doe@Esidem.ca`), dans *Utilisateurs et ordinateurs Active Directory*. Équivalent PowerShell :

```powershell
New-ADUser -Name "Jane Doe" -GivenName "Jane" -Surname "Doe" `
    -SamAccountName "jane.doe" -UserPrincipalName "jane.doe@Esidem.ca" `
    -AccountPassword (Read-Host -AsSecureString "Mot de passe") -Enabled $true
```

## Ce que j'en retiens

- L'ordre compte : **nom → IP fixe → rôles → promotion**. Renommer ou changer l'IP d'un DC après coup casse les enregistrements DNS.
- Le DNS du serveur doit pointer vers lui-même : sans cela, les clients et le DC ne trouvent pas les enregistrements SRV du domaine.
- Un serveur DHCP doit être **autorisé dans Active Directory** avant de distribuer des baux.
- Les comptes créés dans le conteneur `Users` par défaut ne peuvent pas recevoir de GPO dédiées : d'où, dans la suite du lab, une structure en **unités d'organisation**.

La suite du lab automatise et pousse plus loin ces mêmes étapes en PowerShell : voir le [README](../README.md).
