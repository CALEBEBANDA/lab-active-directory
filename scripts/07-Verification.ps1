<#
.SYNOPSIS
    Contrôle rapide de l'état du lab (AD, DNS, DHCP, OU, utilisateurs, GPO).
#>
[CmdletBinding()]
param([string]$OURacine = 'LAB')

Import-Module ActiveDirectory, GroupPolicy, DnsServer, DhcpServer

$domaine = Get-ADDomain
$racine  = "OU=$OURacine,$($domaine.DistinguishedName)"

function Test-Point {
    param([string]$Libelle, [scriptblock]$Test)
    try   { $ok = [bool](& $Test) } catch { $ok = $false }
    $etat = if ($ok) { '[OK]  ' } else { '[KO]  ' }
    $couleur = if ($ok) { 'Green' } else { 'Red' }
    Write-Host "$etat$Libelle" -ForegroundColor $couleur
}

Write-Host "Domaine : $($domaine.DNSRoot)  |  DC : $env:COMPUTERNAME`n" -ForegroundColor Cyan

Test-Point 'Services AD (NTDS, DNS, Netlogon, DHCP) démarrés' {
    -not (Get-Service NTDS, DNS, Netlogon, DHCPServer | Where-Object Status -ne 'Running')
}
Test-Point 'Enregistrements SRV LDAP présents' {
    Resolve-DnsName "_ldap._tcp.dc._msdcs.$($domaine.DNSRoot)" -Type SRV -ErrorAction Stop
}
Test-Point 'Zone de recherche inversée présente' {
    Get-DnsServerZone | Where-Object { $_.IsReverseLookupZone -and -not $_.IsAutoCreated }
}
Test-Point 'Serveur DHCP autorisé dans AD'       { Get-DhcpServerInDC }
Test-Point 'Étendue DHCP active'                  { Get-DhcpServerv4Scope | Where-Object State -eq 'Active' }
Test-Point "OU $OURacine présente"                { Get-ADOrganizationalUnit -Identity $racine }
Test-Point 'Utilisateurs créés dans les OU'      { Get-ADUser -Filter * -SearchBase $racine }
Test-Point 'GPO de restriction liée'             {
    (Get-GPInheritance -Target "OU=Utilisateurs,$racine").GpoLinks.DisplayName -contains 'GPO_Restrictions_Utilisateurs'
}

Write-Host "`nUtilisateurs par service :" -ForegroundColor Cyan
Get-ADUser -Filter * -SearchBase "OU=Utilisateurs,$racine" -Properties Department |
    Group-Object Department | Sort-Object Name | Format-Table Name, Count -AutoSize

Write-Host 'Baux DHCP en cours :' -ForegroundColor Cyan
Get-DhcpServerv4Scope | ForEach-Object { Get-DhcpServerv4Lease -ScopeId $_.ScopeId } |
    Format-Table IPAddress, HostName, AddressState -AutoSize
