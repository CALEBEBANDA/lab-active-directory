<#
.SYNOPSIS
    Crée l'arborescence d'unités d'organisation (OU) et les groupes par service.
.DESCRIPTION
    LAB
     ├─ Utilisateurs
     │   ├─ Comptabilite, RH, Informatique, Direction, Commercial
     ├─ Ordinateurs
     └─ Groupes          (un groupe global GG_<Service> par service)
#>
[CmdletBinding()]
param(
    [string]  $OURacine = 'LAB',
    [string[]]$Services = @('Comptabilite', 'RH', 'Informatique', 'Direction', 'Commercial')
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$domainDN = (Get-ADDomain).DistinguishedName

function New-OUSiAbsente {
    param([string]$Nom, [string]$Parent)
    $dn = "OU=$Nom,$Parent"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $Nom -Path $Parent -ProtectedFromAccidentalDeletion $true
        Write-Host "  + OU $dn" -ForegroundColor Green
    } else {
        Write-Host "  = OU $dn (existe déjà)" -ForegroundColor DarkGray
    }
    return $dn
}

Write-Host 'Création des OU...' -ForegroundColor Cyan
$racine  = New-OUSiAbsente -Nom $OURacine      -Parent $domainDN
$ouUsers = New-OUSiAbsente -Nom 'Utilisateurs' -Parent $racine
$null    = New-OUSiAbsente -Nom 'Ordinateurs'  -Parent $racine
$ouGrp   = New-OUSiAbsente -Nom 'Groupes'      -Parent $racine

foreach ($service in $Services) {
    $null = New-OUSiAbsente -Nom $service -Parent $ouUsers

    $nomGroupe = "GG_$service"
    if (-not (Get-ADGroup -Filter "SamAccountName -eq '$nomGroupe'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $nomGroupe -SamAccountName $nomGroupe -GroupScope Global -GroupCategory Security `
            -Path $ouGrp -Description "Membres du service $service"
        Write-Host "  + Groupe $nomGroupe" -ForegroundColor Green
    }
}

# Les nouveaux ordinateurs joints au domaine arrivent directement dans LAB\Ordinateurs
redircmp "OU=Ordinateurs,$racine" | Out-Null
Write-Host "Conteneur par défaut des ordinateurs redirigé vers OU=Ordinateurs,$racine" -ForegroundColor Cyan
