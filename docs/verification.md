# Tests et validation

Contrôles à effectuer après le déploiement, côté serveur puis côté poste client (Windows 10/11 joint au domaine).

## Côté serveur

```powershell
.\scripts\08-Verification.ps1
```

| Contrôle | Commande | Résultat attendu |
|---|---|---|
| Santé du DC | `dcdiag /q` | Aucune erreur |
| Enregistrements DNS du domaine | `Resolve-DnsName _ldap._tcp.dc._msdcs.lab.local -Type SRV` | SRV pointant vers `SRV-DC01.lab.local` |
| Résolution inverse | `Resolve-DnsName 192.168.10.10` | `SRV-DC01.lab.local` |
| Serveur DHCP autorisé | `Get-DhcpServerInDC` | `SRV-DC01.lab.local` |
| Utilisateurs importés | `Get-ADUser -Filter * -SearchBase "OU=Utilisateurs,OU=LAB,DC=lab,DC=local" \| Measure-Object` | 10 comptes |
| Liens GPO | `Get-GPInheritance "OU=Etudiants,OU=Utilisateurs,OU=LAB,DC=lab,DC=local"` | `GPO_Restriction_Etudiants` |
| Droits du partage | `Get-SmbShareAccess Cours` | Etudiants : Read · Enseignants : Change |

## Côté client

1. Démarrer le poste sur le LAN : `ipconfig /all` montre une adresse entre `192.168.10.110` et `.200`, la passerelle `192.168.10.1`, le DNS `192.168.10.10` et le suffixe `lab.local`.
2. Joindre le domaine : `Add-Computer -DomainName lab.local -Restart` → l'objet ordinateur apparaît dans `OU=Laboratoire,OU=LAB`.
3. Se connecter avec `alice.martin` (Etudiants) → changement de mot de passe imposé à la première connexion.
4. Vérifier les restrictions étudiantes :
   - Panneau de configuration / Paramètres → *« Cette opération a été annulée en raison des restrictions en vigueur sur cet ordinateur »*
   - `regedit` → *« La modification du Registre a été désactivée par votre administrateur »*
   - `cmd` → *« L'invite de commandes a été désactivée par votre administrateur »*
   - Clé USB → accès refusé
5. Ouvrir `\\SRV-DC01\Cours` → les documents s'ouvrent, mais la création ou la suppression d'un fichier est refusée.
6. Se connecter avec `gaelle.petit` (Enseignants) → Panneau de configuration bloqué, mais écriture possible dans `\\SRV-DC01\Cours`.
7. Se connecter avec `farid.richard` (Techniciens) → aucune restriction.
8. Depuis le serveur, `mstsc /v:<nom du poste>` → la connexion Bureau à distance s'ouvre avec un compte administrateur.
9. `gpresult /r` (ou `gpresult /h rapport.html`) pour confirmer les GPO appliquées à chaque utilisateur et à l'ordinateur.

## Problèmes courants

| Symptôme | Cause probable | Correction |
|---|---|---|
| Le client n'obtient pas d'adresse | Serveur DHCP non autorisé dans AD, ou étendue inactive | `Add-DhcpServerInDC`, `Set-DhcpServerv4Scope -State Active` |
| Le client a une IP mais n'atteint pas les autres réseaux | Option 003 (passerelle) absente de l'étendue | `Set-DhcpServerv4OptionValue -Router 192.168.10.1` |
| Échec de jonction au domaine | DNS du client pointant vers la box | DNS du client = IP du DC (option 006 DHCP) |
| GPO non appliquée | Rafraîchissement périodique (~90 min), utilisateur hors de l'OU liée, lien désactivé | `gpupdate /force` puis reconnexion ; vérifier l'OU du compte et `Get-GPInheritance` |
| Bureau à distance refusé | RDP désactivé sur le poste ou pare-feu bloquant le port 3389 | Vérifier que `GPO_Bureau_A_Distance` s'applique (`gpresult /r /scope computer`) |
