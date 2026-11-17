<#
.SYNOPSIS
    Prépare le serveur et le promeut en contrôleur de domaine (nouvelle forêt).
.DESCRIPTION
    Étape 1 (avant redémarrage) : renomme le serveur et fixe l'adresse IP.
    Étape 2 (après redémarrage) : installe AD DS + DNS et crée la forêt.
    À exécuter en tant qu'administrateur local sur Windows Server.
.EXAMPLE
    .\01-Install-ADDS.ps1 -Etape Preparation
    .\01-Install-ADDS.ps1 -Etape Promotion
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Preparation', 'Promotion')]
    [string]$Etape,
    [string]$NomServeur   = 'SRV-DC01',
    [string]$Interface    = 'Ethernet',
    [string]$AdresseIP    = '192.168.10.10',
    [int]   $Prefixe      = 24,
    [string]$Passerelle   = '192.168.10.1',
    [string]$NomDomaine   = 'lab.local',
    [string]$NomNetBIOS   = 'LAB'
)

$ErrorActionPreference = 'Stop'

switch ($Etape) {
    'Preparation' {
        Write-Host "Configuration IP statique sur '$Interface' : $AdresseIP/$Prefixe" -ForegroundColor Cyan
        Get-NetIPAddress -InterfaceAlias $Interface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Remove-NetIPAddress -Confirm:$false
        Get-NetRoute -InterfaceAlias $Interface -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Remove-NetRoute -Confirm:$false
        New-NetIPAddress -InterfaceAlias $Interface -IPAddress $AdresseIP -PrefixLength $Prefixe -DefaultGateway $Passerelle | Out-Null
        # Le futur DC est son propre serveur DNS
        Set-DnsClientServerAddress -InterfaceAlias $Interface -ServerAddresses $AdresseIP

        if ($env:COMPUTERNAME -ne $NomServeur) {
            Write-Host "Renommage du serveur en $NomServeur puis redémarrage..." -ForegroundColor Cyan
            Rename-Computer -NewName $NomServeur -Restart
        }
    }

    'Promotion' {
        Write-Host 'Installation des rôles AD DS et DNS...' -ForegroundColor Cyan
        Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools | Out-Null

        $dsrm = Read-Host -AsSecureString 'Mot de passe du mode restauration (DSRM)'

        Write-Host "Création de la forêt $NomDomaine ($NomNetBIOS)..." -ForegroundColor Cyan
        Import-Module ADDSDeployment
        Install-ADDSForest `
            -DomainName $NomDomaine `
            -DomainNetbiosName $NomNetBIOS `
            -ForestMode 'WinThreshold' `
            -DomainMode 'WinThreshold' `
            -InstallDns:$true `
            -SafeModeAdministratorPassword $dsrm `
            -NoRebootOnCompletion:$false `
            -Force:$true
    }
}
