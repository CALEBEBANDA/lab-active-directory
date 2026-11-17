<#
.SYNOPSIS
    Crée les GPO du laboratoire et les lie aux unités d'organisation.
.DESCRIPTION
    GPO_Restriction_Etudiants    -> OU=Etudiants    (configuration Utilisateur)
        - Panneau de configuration et Paramètres interdits
        - Outils de modification du Registre interdits
        - Invite de commandes interdite (scripts batch autorisés)
        - Stockage amovible (USB) interdit
    GPO_Restriction_Enseignants  -> OU=Enseignants  (configuration Utilisateur)
        - Panneau de configuration et Paramètres interdits
    GPO_Bureau_A_Distance        -> OU=Laboratoire  (configuration Ordinateur)
        - Bureau à distance activé avec authentification NLA
        - Règle de pare-feu entrante TCP 3389 (profil Domaine)
    Les techniciens (OU=Techniciens) ne reçoivent aucune restriction.
#>
[CmdletBinding()]
param([string]$OURacine = 'LAB')

$ErrorActionPreference = 'Stop'
Import-Module GroupPolicy, ActiveDirectory

$domaine = Get-ADDomain
$racine  = "OU=$OURacine,$($domaine.DistinguishedName)"
$ouEtu   = "OU=Etudiants,OU=Utilisateurs,$racine"
$ouEns   = "OU=Enseignants,OU=Utilisateurs,$racine"
$ouLab   = "OU=Laboratoire,$racine"

$cleExplorer = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
$cleSystem   = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System'
$cleCmd      = 'HKCU\Software\Policies\Microsoft\Windows\System'
$cleUSB      = 'HKCU\Software\Policies\Microsoft\Windows\RemovableStorageDevices'
$cleRDP      = 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'

function New-GPOSiAbsente {
    param([string]$Nom, [string]$Commentaire, [ValidateSet('User', 'Computer')][string]$Partie)
    $gpo = Get-GPO -Name $Nom -ErrorAction SilentlyContinue
    if (-not $gpo) {
        $gpo = New-GPO -Name $Nom -Comment $Commentaire
        Write-Host "  + GPO $Nom" -ForegroundColor Green
    }
    # On désactive la partie inutilisée de la GPO : traitement plus rapide à l'ouverture de session
    $gpo.GpoStatus = if ($Partie -eq 'User') { 'ComputerSettingsDisabled' } else { 'UserSettingsDisabled' }
}

function Set-Lien {
    param([string]$Nom, [string]$Cible)
    if ((Get-GPInheritance -Target $Cible).GpoLinks.DisplayName -notcontains $Nom) {
        New-GPLink -Name $Nom -Target $Cible -LinkEnabled Yes | Out-Null
        Write-Host "  -> $Nom liée à $Cible" -ForegroundColor Green
    }
}

function Set-Valeur {
    param([string]$Gpo, [string]$Cle, [string]$Nom, [int]$Valeur)
    Set-GPRegistryValue -Name $Gpo -Key $Cle -ValueName $Nom -Type DWord -Value $Valeur | Out-Null
}

Write-Host 'GPO_Restriction_Etudiants...' -ForegroundColor Cyan
$gpo = 'GPO_Restriction_Etudiants'
New-GPOSiAbsente -Nom $gpo -Partie User -Commentaire 'Restrictions des postes pour les étudiants'
Set-Valeur $gpo $cleExplorer 'NoControlPanel'       1
Set-Valeur $gpo $cleSystem   'DisableRegistryTools' 1
Set-Valeur $gpo $cleCmd      'DisableCMD'           2
Set-Valeur $gpo $cleUSB      'Deny_All'             1
Set-Lien -Nom $gpo -Cible $ouEtu

Write-Host 'GPO_Restriction_Enseignants...' -ForegroundColor Cyan
$gpo = 'GPO_Restriction_Enseignants'
New-GPOSiAbsente -Nom $gpo -Partie User -Commentaire 'Restrictions des postes pour les enseignants'
Set-Valeur $gpo $cleExplorer 'NoControlPanel' 1
Set-Lien -Nom $gpo -Cible $ouEns

Write-Host 'GPO_Bureau_A_Distance...' -ForegroundColor Cyan
$gpo = 'GPO_Bureau_A_Distance'
New-GPOSiAbsente -Nom $gpo -Partie Computer -Commentaire 'Active le Bureau à distance sur les postes du laboratoire'
Set-Valeur $gpo $cleRDP 'fDenyTSConnections' 0   # autorise les connexions RDP
Set-Valeur $gpo $cleRDP 'UserAuthentication' 1   # exige l'authentification NLA
# Règle de pare-feu entrante RDP, limitée au profil Domaine
$session = Open-NetGPO -PolicyStore "$($domaine.DNSRoot)\$gpo"
$regle   = 'Bureau a distance - TCP 3389 (GPO)'
if (-not (Get-NetFirewallRule -GPOSession $session -DisplayName $regle -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -GPOSession $session -DisplayName $regle -Direction Inbound -Protocol TCP `
        -LocalPort 3389 -Action Allow -Profile Domain | Out-Null
}
Save-NetGPO -GPOSession $session
Set-Lien -Nom $gpo -Cible $ouLab

Write-Host "`nGPO effectivement héritées par chaque OU :" -ForegroundColor Cyan
foreach ($cible in $ouEtu, $ouEns, $ouLab) {
    Get-GPInheritance -Target $cible | Select-Object -ExpandProperty InheritedGpoLinks |
        Format-Table DisplayName, Target, Order -AutoSize
}
Write-Host 'Sur le client : gpupdate /force, puis gpresult /r pour vérifier.' -ForegroundColor DarkGray
