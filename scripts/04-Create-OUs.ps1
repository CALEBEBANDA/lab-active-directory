<#
.SYNOPSIS
    Crée l'arborescence d'unités d'organisation (OU) et les groupes du laboratoire.
.DESCRIPTION
    LAB
     ├─ Utilisateurs
     │   ├─ Etudiants
     │   ├─ Enseignants
     │   └─ Techniciens
     ├─ Laboratoire     (postes des étudiants ; nouveaux ordinateurs joints au domaine)
     ├─ Serveurs
     └─ Groupes         (un groupe de sécurité global par profil : Etudiants, Enseignants, Techniciens)
#>
[CmdletBinding()]
param(
    [string]  $OURacine = 'LAB',
    [string[]]$Profils  = @('Etudiants', 'Enseignants', 'Techniciens')
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
$ouLab   = New-OUSiAbsente -Nom 'Laboratoire'  -Parent $racine
$null    = New-OUSiAbsente -Nom 'Serveurs'     -Parent $racine
$ouGrp   = New-OUSiAbsente -Nom 'Groupes'      -Parent $racine

foreach ($profil in $Profils) {
    $null = New-OUSiAbsente -Nom $profil -Parent $ouUsers

    if (-not (Get-ADGroup -Filter "SamAccountName -eq '$profil'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $profil -SamAccountName $profil -GroupScope Global -GroupCategory Security `
            -Path $ouGrp -Description "Groupe de sécurité : $profil"
        Write-Host "  + Groupe $profil" -ForegroundColor Green
    }
}

# Les postes joints au domaine arrivent directement dans l'OU Laboratoire, où s'appliquent les GPO
redircmp $ouLab | Out-Null
Write-Host "Conteneur par défaut des ordinateurs redirigé vers $ouLab" -ForegroundColor Cyan
