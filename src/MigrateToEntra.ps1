function Sync-SkolniLoginHashToEntra {
    <#
    .SYNOPSIS
        Copies the SkolniLogin identity hash (SLHash) from Active Directory users to their
        corresponding Entra ID (Azure AD) accounts via Microsoft Graph.

    .DESCRIPTION
        The SLHash is normally stored in an AD attribute (e.g. msDS-cloudExtensionAttribute1)
        that is not synced to Entra ID by default. This cmdlet reads the hash from AD and writes
        it to the custom directory extension attribute used by the Entra ID provisioning mode,
        matching users by UPN.

        Run this once after enabling Entra ID mode on a tenant where students were previously
        provisioned via Active Directory.

        Prerequisites:
        - ActiveDirectory PowerShell module
        - Microsoft.Graph.Users module
        - An active Graph connection: Connect-MgGraph -Scopes "User.ReadWrite.All"

    .PARAMETER UserOU
        The Active Directory organizational unit (distinguished name) to search for users.

    .PARAMETER ExtensionAttributeAppId
        The App ID (with hyphens) of the app registration on which the skolniLoginHash extension
        attribute was registered. Used to compute the attribute name:
        extension_<AppIdWithoutHyphens>_skolniLoginHash

    .PARAMETER ExtensionAttributeName
        The Active Directory attribute that holds the SLHash. Defaults to
        'msDS-cloudExtensionAttribute1'.

    .PARAMETER Force
        If specified, overwrites the Entra extension attribute even if it is already set on
        the Entra user. By default, users whose Entra attribute is already populated are skipped.

    .EXAMPLE
        Sync-SkolniLoginHashToEntra `
            -UserOU "OU=Students,OU=Users,DC=ad,DC=skola,DC=cz" `
            -ExtensionAttributeAppId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

    .EXAMPLE
        Sync-SkolniLoginHashToEntra `
            -UserOU "OU=Students,OU=Users,DC=ad,DC=skola,DC=cz" `
            -ExtensionAttributeAppId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
            -ExtensionAttributeName "extensionAttribute1" `
            -Force
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserOU,

        [Parameter(Mandatory = $true)]
        [string]$ExtensionAttributeAppId,

        [string]$ExtensionAttributeName = "msDS-cloudExtensionAttribute1",

        [switch]$Force
    )

    Assert-SkolniLoginMgGraphConnection

    $normalizedAppId = $ExtensionAttributeAppId.Replace("-", "")
    $extensionAttrName = "extension_${normalizedAppId}_skolniLoginHash"

    Write-Debug "Using Entra extension attribute: $extensionAttrName"
    Write-Debug "Reading AD users from OU: $UserOU"

    $adUsers = Get-ADUser -SearchBase $UserOU -Filter * `
        -Properties $ExtensionAttributeName, UserPrincipalName |
        Where-Object { -not [string]::IsNullOrEmpty($_.$ExtensionAttributeName) }

    $total = ($adUsers | Measure-Object).Count
    Write-Host "Found $total AD user(s) with '$ExtensionAttributeName' set in '$UserOU'."

    $countSynced = 0
    $countAlreadySet = 0
    $countNotFound = 0
    $countError = 0

    foreach ($adUser in $adUsers) {
        $upn = $adUser.UserPrincipalName
        $hash = $adUser.$ExtensionAttributeName

        if ([string]::IsNullOrEmpty($upn)) {
            Write-Warning "AD user '$($adUser.SamAccountName)' has no UPN — skipping."
            $countError++
            continue
        }

        try {
            $mgUser = Get-MgUser `
                -Filter "userPrincipalName eq '$upn'" `
                -Property "id,userPrincipalName,$extensionAttrName" `
                -ErrorAction Stop | Select-Object -First 1
        }
        catch {
            Write-Warning "Graph lookup failed for '$upn': $_"
            $countError++
            continue
        }

        if ($null -eq $mgUser) {
            Write-Warning "Entra user not found for UPN '$upn' — skipping."
            $countNotFound++
            continue
        }

        $existingValue = $mgUser.AdditionalProperties[$extensionAttrName]

        if (-not [string]::IsNullOrEmpty($existingValue) -and -not $Force) {
            Write-Debug "Entra user '$upn' already has '$extensionAttrName' set — skipping (use -Force to overwrite)."
            $countAlreadySet++
            continue
        }

        if ($PSCmdlet.ShouldProcess($upn, "Set $extensionAttrName = $hash")) {
            try {
                Update-MgUser -UserId $mgUser.Id `
                    -AdditionalProperties @{ $extensionAttrName = $hash } `
                    -ErrorAction Stop
                Write-Debug "Synced hash for '$upn'."
                $countSynced++
            }
            catch {
                Write-Warning "Failed to update Entra user '$upn': $_"
                $countError++
            }
        }
        else {
            # -WhatIf: count what would have been synced so the summary is meaningful
            $countSynced++
        }
    }

    Write-Host ""
    Write-Host "Sync-SkolniLoginHashToEntra completed:"
    Write-Host "  Synced:      $countSynced"
    Write-Host "  Already set: $countAlreadySet"
    Write-Host "  Not found:   $countNotFound"
    Write-Host "  Errors:      $countError"
}
