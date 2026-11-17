<#
.SYNOPSIS
    Crée le dossier partagé « Cours » avec des droits par groupe.
.DESCRIPTION
    Dossier C:\Partages\Cours partagé en \\<serveur>\Cours :
        Groupe          Partage (SMB)   NTFS
        Etudiants       Lecture         Lecture et exécution   -> consultent sans modifier ni supprimer
        Enseignants     Modifier        Modification           -> déposent et mettent à jour les documents
        Administrateurs Contrôle total  Contrôle total
    L'héritage NTFS est désactivé et le groupe « Utilisateurs » retiré :
    seuls les groupes ci-dessus ont accès. L'énumération basée sur l'accès
    masque le partage aux utilisateurs qui n'y ont pas droit.
#>
[CmdletBinding()]
param(
    [string]$Chemin     = 'C:\Partages\Cours',
    [string]$NomPartage = 'Cours'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory, SmbShare

$netbios = (Get-ADDomain).NetBIOSName
$etu     = "$netbios\Etudiants"
$ens     = "$netbios\Enseignants"
# Noms localisés (Administrateurs / Administrators...) résolus depuis les SID connus
$admins  = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value
$system  = New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'

if (-not (Test-Path $Chemin)) {
    New-Item -Path $Chemin -ItemType Directory | Out-Null
    Write-Host "  + Dossier $Chemin" -ForegroundColor Green
}

Write-Host 'Permissions NTFS...' -ForegroundColor Cyan
$acl = Get-Acl $Chemin
$acl.SetAccessRuleProtection($true, $false)   # désactive l'héritage sans copier les règles héritées
$acl.Access | ForEach-Object { [void]$acl.RemoveAccessRule($_) }
$heritage = 'ContainerInherit, ObjectInherit'
foreach ($r in @(
    @($admins, 'FullControl'),
    @($system, 'FullControl'),
    @($ens,    'Modify'),
    @($etu,    'ReadAndExecute')
)) {
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($r[0], $r[1], $heritage, 'None', 'Allow')))
}
Set-Acl -Path $Chemin -AclObject $acl

Write-Host 'Partage SMB...' -ForegroundColor Cyan
if (-not (Get-SmbShare -Name $NomPartage -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $NomPartage -Path $Chemin -FullAccess $admins -ChangeAccess $ens -ReadAccess $etu `
        -FolderEnumerationMode AccessBased -Description 'Documents pédagogiques' | Out-Null
    Write-Host "  + \\$env:COMPUTERNAME\$NomPartage" -ForegroundColor Green
}

Get-SmbShareAccess -Name $NomPartage | Format-Table AccountName, AccessRight -AutoSize
(Get-Acl $Chemin).Access | Format-Table IdentityReference, FileSystemRights, IsInherited -AutoSize
