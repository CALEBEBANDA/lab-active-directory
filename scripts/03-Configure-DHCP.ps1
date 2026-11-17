<#
.SYNOPSIS
    Installe et configure le rôle DHCP sur le contrôleur de domaine.
.DESCRIPTION
    - Installe le rôle DHCP et crée les groupes de sécurité DHCP.
    - Autorise le serveur dans Active Directory.
    - Crée l'étendue et ses options (routeur, DNS, domaine).
    - Ajoute une exclusion pour les adresses statiques (serveurs, imprimantes).
#>
[CmdletBinding()]
param(
    [string]$NomDomaine     = 'lab.local',
    [string]$NomServeur     = 'SRV-DC01',
    [string]$AdresseIP      = '192.168.10.10',
    [string]$NomEtendue     = 'LAN-Clients',
    [string]$ScopeId        = '192.168.10.0',
    [string]$Debut          = '192.168.10.100',
    [string]$Fin            = '192.168.10.200',
    [string]$Masque         = '255.255.255.0',
    [string]$Passerelle     = '192.168.10.1',
    [string]$ExclusionDebut = '192.168.10.100',
    [string]$ExclusionFin   = '192.168.10.109',
    [int]   $DureeBailJours = 8
)

$ErrorActionPreference = 'Stop'

Write-Host 'Installation du rôle DHCP...' -ForegroundColor Cyan
Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null

# Groupes "Administrateurs DHCP" et "Utilisateurs DHCP"
netsh dhcp add securitygroups | Out-Null
Restart-Service DHCPServer

$fqdn = "$NomServeur.$NomDomaine"
if (-not (Get-DhcpServerInDC | Where-Object DnsName -eq $fqdn)) {
    Write-Host "Autorisation de $fqdn dans AD" -ForegroundColor Cyan
    Add-DhcpServerInDC -DnsName $fqdn -IPAddress $AdresseIP
}

# Supprime l'avertissement "configuration post-installation" du Gestionnaire de serveur
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12' -Name ConfigurationState -Value 2

if (-not (Get-DhcpServerv4Scope -ScopeId $ScopeId -ErrorAction SilentlyContinue)) {
    Write-Host "Création de l'étendue $NomEtendue ($Debut - $Fin)" -ForegroundColor Cyan
    Add-DhcpServerv4Scope -Name $NomEtendue -StartRange $Debut -EndRange $Fin -SubnetMask $Masque `
        -LeaseDuration (New-TimeSpan -Days $DureeBailJours) -State Active
}

Set-DhcpServerv4OptionValue -ScopeId $ScopeId -Router $Passerelle -DnsServer $AdresseIP -DnsDomain $NomDomaine

if (-not (Get-DhcpServerv4ExclusionRange -ScopeId $ScopeId -ErrorAction SilentlyContinue)) {
    Add-DhcpServerv4ExclusionRange -ScopeId $ScopeId -StartRange $ExclusionDebut -EndRange $ExclusionFin
}

# Mise à jour DNS dynamique des enregistrements des clients
Set-DhcpServerv4DnsSetting -ScopeId $ScopeId -DynamicUpdates Always -DeleteDnsRROnLeaseExpiry $true

Get-DhcpServerv4Scope | Format-Table ScopeId, Name, StartRange, EndRange, State -AutoSize
