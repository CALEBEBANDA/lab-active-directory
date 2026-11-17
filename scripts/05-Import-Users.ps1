<#
.SYNOPSIS
    Crée des comptes utilisateurs en masse depuis un fichier CSV.
.DESCRIPTION
    Pour chaque ligne du CSV (Prenom;Nom;Service;Fonction;Telephone) :
    - génère un identifiant unique au format prenom.nom (sans accents, 20 car. max) ;
    - crée le compte dans OU=<Service>,OU=Utilisateurs,OU=LAB (Etudiants, Enseignants, Techniciens) ;
    - l'ajoute au groupe de sécurité du même nom ;
    - impose le changement du mot de passe initial à la première connexion.
    Le mot de passe initial est demandé au lancement (jamais stocké dans le CSV).
.EXAMPLE
    .\05-Import-Users.ps1 -CheminCsv ..\data\utilisateurs.csv
    .\05-Import-Users.ps1 -CheminCsv ..\data\utilisateurs.csv -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })]
    [string]$CheminCsv,
    [string]$OURacine  = 'LAB',
    [char]  $Delimiteur = ';'
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

function Remove-Accents {
    param([string]$Texte)
    $normalise = $Texte.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $normalise.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne 'NonSpacingMark') { [void]$sb.Append($c) }
    }
    return ($sb.ToString() -replace '[^a-zA-Z0-9\-]', '').ToLower()
}

$domaine   = Get-ADDomain
$suffixUPN = $domaine.DNSRoot
$motDePasse = Read-Host -AsSecureString 'Mot de passe initial des comptes (changement imposé à la 1re connexion)'

$utilisateurs = Import-Csv -Path $CheminCsv -Delimiter $Delimiteur -Encoding UTF8
$bilan = @{ Crees = 0; Ignores = 0; Erreurs = 0 }

foreach ($u in $utilisateurs) {
    $prenom = $u.Prenom.Trim()
    $nom    = $u.Nom.Trim()
    $ou     = "OU=$($u.Service),OU=Utilisateurs,OU=$OURacine,$($domaine.DistinguishedName)"

    # Identifiant prenom.nom tronqué à 20 caractères (limite sAMAccountName), suffixe numérique si doublon
    $base = ('{0}.{1}' -f (Remove-Accents $prenom), (Remove-Accents $nom))
    if ($base.Length -gt 20) { $base = $base.Substring(0, 20) }
    $sam = $base; $i = 1
    while (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        # Compte identique (même nom complet) déjà présent : on l'ignore
        $existant = Get-ADUser -Identity $sam -Properties GivenName, Surname
        if ($existant.GivenName -eq $prenom -and $existant.Surname -eq $nom) { $sam = $null; break }
        $suffixe = [string]$i++
        $sam = $base.Substring(0, [Math]::Min($base.Length, 20 - $suffixe.Length)) + $suffixe
    }

    if (-not $sam) {
        Write-Host "  = $prenom $nom existe déjà, ignoré" -ForegroundColor DarkGray
        $bilan.Ignores++
        continue
    }

    try {
        if ($PSCmdlet.ShouldProcess("$prenom $nom ($sam)", "Créer dans $ou")) {
            New-ADUser `
                -Name "$prenom $nom" -DisplayName "$prenom $nom" `
                -GivenName $prenom -Surname $nom `
                -SamAccountName $sam -UserPrincipalName "$sam@$suffixUPN" `
                -Department $u.Service -Title $u.Fonction `
                -Path $ou -AccountPassword $motDePasse `
                -ChangePasswordAtLogon $true -Enabled $true

            if ($u.Telephone) { Set-ADUser -Identity $sam -OfficePhone $u.Telephone }
            Add-ADGroupMember -Identity $u.Service -Members $sam
            Write-Host "  + $sam ($($u.Service))" -ForegroundColor Green
            $bilan.Crees++
        }
    } catch {
        Write-Warning "Échec pour $prenom $nom : $($_.Exception.Message)"
        $bilan.Erreurs++
    }
}

Write-Host ("`nBilan : {0} créé(s), {1} ignoré(s), {2} erreur(s)" -f $bilan.Crees, $bilan.Ignores, $bilan.Erreurs) -ForegroundColor Cyan
