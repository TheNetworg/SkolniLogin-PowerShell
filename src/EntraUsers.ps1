function Get-SkolniLoginEntraUserByHash {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SLHash,
        [Parameter(Mandatory = $true)]
        [string]$ExtensionAttributeAppId,
        # Name of the onPremisesExtensionAttributes field to fall back to for AD-synced users.
        # Corresponds to whatever Entra attribute the AD ExtensionAttributeName syncs to.
        [string]$FallbackExtensionAttributeName = "extensionAttribute1"
    )

    $normalizedAppId = $ExtensionAttributeAppId.Replace("-", "")
    $extensionAttrName = "extension_${normalizedAppId}_skolniLoginHash"

    # Search by the custom Entra directory extension attribute first
    $user = Get-MgUser `
        -Filter "$extensionAttrName eq '$SLHash'" `
        -ConsistencyLevel "eventual" `
        -CountVariable slCount1 `
        -Property "id,displayName,userPrincipalName,givenName,surname,$extensionAttrName" `
        -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($null -ne $user) {
        return $user
    }

    # Migration fallback: users previously provisioned via Active Directory and synced to Entra
    # will have the SLHash stored in onPremisesExtensionAttributes
    $user = Get-MgUser `
        -Filter "onPremisesExtensionAttributes/$FallbackExtensionAttributeName eq '$SLHash'" `
        -ConsistencyLevel "eventual" `
        -CountVariable slCount2 `
        -Property "id,displayName,userPrincipalName,givenName,surname,onPremisesExtensionAttributes" `
        -ErrorAction SilentlyContinue | Select-Object -First 1

    return $user
}

function New-SkolniLoginEntraUsername {
    param (
        [Parameter(Mandatory = $true)]
        $GivenName,
        [Parameter(Mandatory = $true)]
        $Surname,
        [Parameter(Mandatory = $true)]
        $Pattern,
        [Parameter(Mandatory = $true)]
        $Domain
    )

    $GivenName = ($GivenName.Normalize("FormD") -replace '\p{M}', '').Trim()
    $GivenName = $GivenName.Split(" ")[0]
    $Surname = ($Surname.Normalize("FormD") -replace '\p{M}', '').Trim()
    $Surname = $Surname.Split(" ")[-1]

    $alias = ""
    $i = 0

    # PrijmeniJme0, PrijmeniJme1, ...
    if ($Pattern -eq 1) {
        $end = [Math]::Min(3, $GivenName.Length)
        $alias = "$Surname$($GivenName.Substring(0, $end))$i"
        while (Get-MgUser -Filter "userPrincipalName eq '$alias@$Domain'" -ErrorAction SilentlyContinue) {
            $i++
            $alias = "$Surname$($GivenName.Substring(0, $end))$i"
        }
    }
    # Jmeno.Prijmeni, Jmeno.Prijmeni.1, ...
    elseif ($Pattern -eq 2) {
        $alias = "$GivenName.$Surname"
        while (Get-MgUser -Filter "userPrincipalName eq '$alias@$Domain'" -ErrorAction SilentlyContinue) {
            $i++
            $alias = "$GivenName.$Surname.$i"
        }
    }
    # Prijmeni.Jmeno, Prijmeni.Jmeno.1, ...
    elseif ($Pattern -eq 3) {
        $alias = "$Surname.$GivenName"
        while (Get-MgUser -Filter "userPrincipalName eq '$alias@$Domain'" -ErrorAction SilentlyContinue) {
            $i++
            $alias = "$Surname.$GivenName.$i"
        }
    }
    # JmenoPrijmeni, JmenoPrijmeni2, ...
    elseif ($Pattern -eq 4) {
        $alias = "$GivenName$Surname"
        $i++
        while (Get-MgUser -Filter "userPrincipalName eq '$alias@$Domain'" -ErrorAction SilentlyContinue) {
            $i++
            $alias = "$GivenName$Surname$i"
        }
    }
    # PrijmeniJ, PrijmeniJ1, ...
    elseif ($Pattern -eq 5) {
        $end = [Math]::Min(1, $GivenName.Length)
        $alias = "$Surname$($GivenName.Substring(0, $end))"
        while (Get-MgUser -Filter "userPrincipalName eq '$alias@$Domain'" -ErrorAction SilentlyContinue) {
            $i++
            $alias = "$Surname$($GivenName.Substring(0, $end))$i"
        }
    }

    return $alias
}

function New-SkolniLoginEntraUser {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter(Mandatory = $true)]
        [ref]$User,
        [Parameter(Mandatory = $true)]
        [int]$Pattern,
        [Parameter(Mandatory = $true)]
        [int]$DisplayNamePattern,
        [Parameter(Mandatory = $true)]
        [string]$ExtensionAttributeAppId,
        # Corresponds to the AD ExtensionAttributeName as it appears in Entra (for migration fallback)
        [string]$FallbackExtensionAttributeName = "extensionAttribute1"
    )

    if ($User.Value.IDType -eq "BN") {
        $User.Value.ID = $User.Value.ID.Replace("/", "")
    }

    $SLHash = Get-SkolniLoginUserHash -Issuer $User.Value.IDIssuer -Type $User.Value.IDType -Value $User.Value.ID
    $normalizedAppId = $ExtensionAttributeAppId.Replace("-", "")
    $extensionAttrName = "extension_${normalizedAppId}_skolniLoginHash"
    $DisplayName = New-SkolniLoginDisplayName -GivenName $User.Value.GivenName -Surname $User.Value.Surname -Pattern $DisplayNamePattern

    $mgUser = Get-SkolniLoginEntraUserByHash `
        -SLHash $SLHash `
        -ExtensionAttributeAppId $ExtensionAttributeAppId `
        -FallbackExtensionAttributeName $FallbackExtensionAttributeName

    if ($mgUser) {
        Write-Debug "User already exists in Entra ID, updating: $($mgUser.UserPrincipalName)"

        Update-MgUser -UserId $mgUser.Id `
            -GivenName $User.Value.GivenName `
            -Surname $User.Value.Surname `
            -DisplayName $DisplayName `
            -AdditionalProperties @{ $extensionAttrName = $SLHash }

        $User.Value.Status = "Updated"
        $User.Value.UserPrincipalName = $mgUser.UserPrincipalName
        $User.Value.Alias = $mgUser.UserPrincipalName.Split("@")[0]
    }
    else {
        if ([string]::IsNullOrEmpty($User.Value.Alias)) {
            $User.Value.Alias = New-SkolniLoginEntraUsername `
                -GivenName $User.Value.GivenName `
                -Surname $User.Value.Surname `
                -Pattern $Pattern `
                -Domain $Domain
        }

        if ($User.Value.Alias.Length -gt 19) {
            $hash = Get-StringHash $User.Value.ID
            $User.Value.Alias = "user_$($hash.Substring(0, 10))"
        }

        $UserPrincipalName = "$($User.Value.Alias)@$Domain"
        Write-Debug "Creating new Entra ID user: $UserPrincipalName"

        $passPart1 = Get-RandomCharacters -length 4 -characters "abcdefghijklmnopqrstuvwxyz"
        $passPart2 = Get-RandomCharacters -length 4 -characters "0123456789"
        $password = "SL_$passPart1$passPart2"

        try {
            $mgUser = New-MgUser `
                -DisplayName $DisplayName `
                -GivenName $User.Value.GivenName.Trim() `
                -Surname $User.Value.Surname.Trim() `
                -UserPrincipalName $UserPrincipalName `
                -MailNickname $User.Value.Alias `
                -AccountEnabled $true `
                -PasswordProfile @{
                    Password                      = $password
                    ForceChangePasswordNextSignIn = $false
                } `
                -AdditionalProperties @{ $extensionAttrName = $SLHash }

            # Only write credentials to the output row after the account is confirmed created
            $User.Value.Password = $password
            $User.Value.UserPrincipalName = $UserPrincipalName
            $User.Value.Status = "Created"
        }
        catch {
            # Clear any partial state so the output CSV doesn't contain credentials for a
            # user account that was never actually created
            $User.Value.Password = $null
            $User.Value.UserPrincipalName = $null
            $User.Value.Alias = $null
            throw
        }
    }

    return $mgUser
}
