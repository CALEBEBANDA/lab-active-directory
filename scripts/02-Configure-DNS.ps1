<#
.SYNOPSIS
    Finalise la configuration DNS du domaine.
.DESCRIPTION
    - Crée la zone de recherche inversée (intégrée à AD).
    - Ajoute l'enregistrement PTR du contrôleur de domaine.
    - Configure les redirecteurs vers des DNS publics.
#>
[CmdletBinding()]
param(
    [string]  $NetworkId    = '192.168.10.0/24',
    [string]  $NomDomaine   = 'lab.local',
    [string]  $NomServeur   = 'SRV-DC01',
    [string]  $AdresseIP    = '192.168.10.10',
    [string[]]$Redirecteurs = @('1.1.1.1', '8.8.8.8')
)

$ErrorActionPreference = 'Stop'
Import-Module DnsServer

# Nom de la zone inverse : 10.168.192.in-addr.arpa
$octets   = $AdresseIP.Split('.')
$zoneInv  = '{0}.{1}.{2}.in-addr.arpa' -f $octets[2], $octets[1], $octets[0]

if (-not (Get-DnsServerZone -Name $zoneInv -ErrorAction SilentlyContinue)) {
    Write-Host "Création de la zone inverse $zoneInv" -ForegroundColor Cyan
    Add-DnsServerPrimaryZone -NetworkId $NetworkId -ReplicationScope Domain -DynamicUpdate Secure
}

if (-not (Get-DnsServerResourceRecord -ZoneName $zoneInv -Name $octets[3] -RRType Ptr -ErrorAction SilentlyContinue)) {
    Write-Host "Ajout du PTR $AdresseIP -> $NomServeur.$NomDomaine" -ForegroundColor Cyan
    Add-DnsServerResourceRecordPtr -ZoneName $zoneInv -Name $octets[3] -PtrDomainName "$NomServeur.$NomDomaine"
}

Write-Host "Redirecteurs : $($Redirecteurs -join ', ')" -ForegroundColor Cyan
Set-DnsServerForwarder -IPAddress $Redirecteurs

Get-DnsServerZone | Format-Table ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone -AutoSize
