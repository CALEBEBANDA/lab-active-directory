<#
.SYNOPSIS
    Crée des GPO de restriction et les lie aux unités d'organisation.
.DESCRIPTION
    GPO_Restrictions_Utilisateurs  -> liée à OU=Utilisateurs,OU=LAB (tous les services)
        - Panneau de configuration et Paramètres interdits
        - Outils de modification du Registre interdits
        - Invite de commandes interdite (scripts batch autorisés)
        - Accès en lecture/écriture aux stockages amovibles (USB) interdit
    GPO_Exception_Informatique     -> liée à OU=Informatique (lien prioritaire)
        - Ré-autorise le Panneau de configuration, le Registre et l'invite de commandes
          pour le service informatique.
    GPO_Fond_Ecran_Entreprise      -> liée à OU=Utilisateurs,OU=LAB
        - Impose un fond d'écran depuis le partage NETLOGON.
#>
[CmdletBinding()]
param(
    [string]$OURacine     = 'LAB',
    [string]$FondEcran    = 'fond-ecran.jpg'
)

$ErrorActionPreference = 'Stop'
Import-Module GroupPolicy, ActiveDirectory

$domaine   = Get-ADDomain
$ouUsers   = "OU=Utilisateurs,OU=$OURacine,$($domaine.DistinguishedName)"
$ouInfo    = "OU=Informatique,$ouUsers"

$cleExplorer = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$cleSystem   = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System'
$cleCmd      = 'HKCU\Software\Policies\Microsoft\Windows\System'
$cleUSB      = 'HKCU\Software\Policies\Microsoft\Windows\RemovableStorageDevices'

function New-GPOSiAbsente {
    param([string]$Nom, [string]$Commentaire)
    $gpo = Get-GPO -Name $Nom -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $Nom -Comment $Commentaire
        Write-Host "  + GPO $Nom" -ForegroundColor Green
    }
    # Seule la partie Utilisateur est utilisée : on désactive la partie Ordinateur (traitement plus rapide)
    $gpo.GpoStatus = 'ComputerSettingsDisabled'
    return $gpo
}

function Set-Lien {
    param([string]$Nom, [string]$Cible, [int]$Ordre = 1)
    $liens = (Get-GPInheritance -Target $Cible).GpoLinks
    if ($liens.DisplayName -notcontains $Nom) {
        New-GPLink -Name $Nom -Target $Cible -LinkEnabled Yes -Order $Ordre | Out-Null
        Write-Host "  -> $Nom liée à $Cible" -ForegroundColor Green
    }
}

Write-Host 'GPO de restriction...' -ForegroundColor Cyan
$nom = 'GPO_Restrictions_Utilisateurs'
$null = New-GPOSiAbsente -Nom $nom -Commentaire 'Restrictions poste de travail pour les utilisateurs standards'
Set-GPRegistryValue -Name $nom -Key $cleExplorer -ValueName 'NoControlPanel'       -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $nom -Key $cleSystem   -ValueName 'DisableRegistryTools' -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $nom -Key $cleCmd      -ValueName 'DisableCMD'           -Type DWord -Value 2 | Out-Null
Set-GPRegistryValue -Name $nom -Key $cleUSB      -ValueName 'Deny_All'             -Type DWord -Value 1 | Out-Null
Set-Lien -Nom $nom -Cible $ouUsers

Write-Host 'GPO d''exception pour le service informatique...' -ForegroundColor Cyan
$nom = 'GPO_Exception_Informatique'
$null = New-GPOSiAbsente -Nom $nom -Commentaire 'Lève les restrictions pour le service informatique'
Set-GPRegistryValue -Name $nom -Key $cleExplorer -ValueName 'NoControlPanel'       -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $nom -Key $cleSystem   -ValueName 'DisableRegistryTools' -Type DWord -Value 0 | Out-Null
Set-GPRegistryValue -Name $nom -Key $cleCmd      -ValueName 'DisableCMD'           -Type DWord -Value 0 | Out-Null
# Liée plus près de l'objet utilisateur : elle s'applique après (et l'emporte sur) la GPO de restriction
Set-Lien -Nom $nom -Cible $ouInfo

Write-Host 'GPO fond d''écran...' -ForegroundColor Cyan
$nom = 'GPO_Fond_Ecran_Entreprise'
$chemin = "\\$($domaine.DNSRoot)\NETLOGON\$FondEcran"
$null = New-GPOSiAbsente -Nom $nom -Commentaire 'Fond d''écran imposé'
Set-GPRegistryValue -Name $nom -Key $cleSystem -ValueName 'Wallpaper'      -Type String -Value $chemin | Out-Null
Set-GPRegistryValue -Name $nom -Key $cleSystem -ValueName 'WallpaperStyle' -Type String -Value '4'     | Out-Null
Set-Lien -Nom $nom -Cible $ouUsers -Ordre 2
Write-Host "  (déposer l'image dans $chemin)" -ForegroundColor DarkGray

Write-Host "`nHéritage des GPO :" -ForegroundColor Cyan
foreach ($cible in $ouUsers, $ouInfo) {
    Get-GPInheritance -Target $cible | Select-Object -ExpandProperty InheritedGpoLinks |
        Format-Table DisplayName, Target, Order -AutoSize
}
