function New-SkolniLoginUser {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter(Mandatory = $true)]
        [ref]$User,
        [Parameter(Mandatory = $true)]
        [int]$Pattern,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$ExtensionAttributeName = "msDS-cloudExtensionAttribute1"
    )

    if ([string]::IsNullOrEmpty($User.Value.Alias)) {
        $User.Value.Alias = New-SkolniLoginUsername -GivenName $User.Value.GivenName -Surname $User.Value.Surname -Pattern $Pattern -Domain $Domain
    }

    $UserPrincipalName = "$($User.Value.Alias)@$Domain";
    if($User.Value.Alias.Length -gt 19) {
        $hash = Get-StringHash $User.Value.ID;
        $User.Value.Alias = "user_$($hash.Substring(0, 10))";
    }

    if($User.Value.IDType -eq "BN") {
        $User.Value.ID = $User.Value.ID.Replace("/", "");
    }
    $SLHash = Get-SkolniLoginUserHash -Issuer $User.Value.IDIssuer -Type $User.Value.IDType -Value $User.Value.ID
    
    $adUser = Get-ADUser -Filter "$ExtensionAttributeName -eq '$SLHash'"
    $DisplayName = "$($User.Value.GivenName.Trim()) $($User.Value.Surname.Trim())";

    if($adUser) {
        Write-Debug "User already exists, we are going to update them: $($adUser.UserPrincipalName)";

        $adUser | Set-ADUser -GivenName $User.Value.GivenName -Surname $User.Value.Surname -DisplayName $DisplayName;

        $User.Value.Status = "Updated";
        $User.Value.UserPrincipalName = $adUser.UserPrincipalName
        $User.Value.Alias = $adUser.samAccountName
    }
    else {
        Write-Debug "User doesn't exist yet, creating a new one: $UserPrincipalName";

        $passPart1 = Get-RandomCharacters -length 4 -characters "abcdefghijklmnopqrstuvwxyz"
        $passPart2 = Get-RandomCharacters -length 4 -characters "0123456789"
        $User.Value.Password = "SL_$passPart1$passPart2";
        $secureString = ConvertTo-SecureString -String $User.Value.Password -AsPlainText -Force

        $User.Value.UserPrincipalName = $UserPrincipalName

        $adUser = New-ADUser -SamAccountName $User.Value.Alias `
            -Name $UserPrincipalname `
            -UserPrincipalName $UserPrincipalName `
            -GivenName $User.Value.GivenName.Trim() `
            -Surname $User.Value.Surname.Trim() `
            -DisplayName $DisplayName `
            -Path $Path `
            -AccountPassword $secureString `
            -OtherAttributes @{"$ExtensionAttributeName" = $SLHash} `
            -Enabled $true `
            -PassThru

        $User.Value.Status = "Created";
    }

    return $adUser;
}
function New-SkolniLoginUsername {
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

    $alias = "";
    $i = 0;

    # PrijmeniJme0, PrijmeniJme1, ...
    if($Pattern -eq 1) {
        $alias = "$Surname$($GivenName.Substring(0, 3))$i";
        while (Get-ADUser -Filter "UserPrincipalName -eq '$alias@$Domain' -or samAccountName -eq '$alias'") {
            $i++;
            $end = 3
            if($GivenName.Length -lt $end) {
                $end = $GivenName.Length
            }
            $alias = "$Surname$($GivenName.Substring(0, $end))$i";
        }
    }
    # Jmeno.Prijmeni, Jmeno.Prijmeni.1, ...
    elseif ($Pattern -eq 2) {
        $alias = "$GivenName.$Surname";
        while (Get-ADUser -Filter "UserPrincipalName -eq '$alias@$Domain' -or samAccountName -eq '$alias'") {
            $i++;
            $alias = "$GivenName.$Surname.$i";
        }
    }
    # Prijmeno.Jmeno, Prijmeno.Jmeno.1, ...
    elseif ($Pattern -eq 3) {
        $alias = "$Surname.$GivenName";
        while (Get-ADUser -Filter "UserPrincipalName -eq '$alias@$Domain' -or samAccountName -eq '$alias'") {
            $i++;
            $alias = "$Surname.$GivenName.$i";
        }
    }

    return $alias;
}
function Get-SkolniLoginUserHash {
    param (
        [Parameter(Mandatory = $true)]
        $Issuer,
        [Parameter(Mandatory = $true)]
        $Type,
        [Parameter(Mandatory = $true)]
        $Value
    )

    $hash = Get-StringHash $Value
    return "$Issuer,$Type,$hash"
}
