# Tests et validation

Contrôles réalisés après le déploiement, côté serveur puis côté poste client (Windows 10/11 joint au domaine).

## Côté serveur

```powershell
.\scripts\07-Verification.ps1
```

| Contrôle | Commande | Résultat attendu |
|---|---|---|
| Santé du DC | `dcdiag /q` | Aucune erreur |
| Enregistrements DNS du domaine | `Resolve-DnsName _ldap._tcp.dc._msdcs.lab.local -Type SRV` | SRV pointant vers `SRV-DC01.lab.local` |
| Résolution inverse | `Resolve-DnsName 192.168.10.10` | `SRV-DC01.lab.local` |
| Serveur DHCP autorisé | `Get-DhcpServerInDC` | `SRV-DC01.lab.local` |
| Utilisateurs importés | `Get-ADUser -Filter * -SearchBase "OU=Utilisateurs,OU=LAB,DC=lab,DC=local" \| Measure-Object` | 10 comptes |
| Liens GPO | `Get-GPInheritance "OU=Informatique,OU=Utilisateurs,OU=LAB,DC=lab,DC=local"` | `GPO_Exception_Informatique` en ordre 1 |

## Côté client

1. Démarrer le poste sur le LAN : `ipconfig /all` montre une adresse en `192.168.10.110+`, DNS `192.168.10.10`, suffixe `lab.local`.
2. Joindre le domaine : `Add-Computer -DomainName lab.local -Restart` → l'objet ordinateur apparaît dans `OU=Ordinateurs,OU=LAB`.
3. Se connecter avec `alice.martin` (Comptabilité) → changement de mot de passe imposé.
4. Vérifier les restrictions :
   - Panneau de configuration / Paramètres → *« Cette opération a été annulée en raison de restrictions »*
   - `regedit` → *« La modification du Registre a été désactivée par votre administrateur »*
   - `cmd` → *« L'invite de commandes a été désactivée par votre administrateur »*
   - Clé USB → accès refusé
5. Se connecter avec `farid.richard` (Informatique) → Panneau de configuration, `regedit` et `cmd` accessibles.
6. `gpresult /r` (ou `gpresult /h rapport.html`) pour confirmer les GPO appliquées à chaque utilisateur.

## Problèmes courants

| Symptôme | Cause | Correction |
|---|---|---|
| Le client n'obtient pas d'adresse | Serveur DHCP non autorisé dans AD | `Add-DhcpServerInDC` |
| Échec de jonction au domaine | DNS du client pointant vers la box | DNS du client = IP du DC (option 006 DHCP) |
| GPO non appliquée immédiatement | Rafraîchissement périodique (~90 min) | `gpupdate /force` puis reconnexion |
