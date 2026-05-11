function Import-SkolniLoginStudents {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$CurrentYear,
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter(Mandatory = $true)]
        [string]$UserGroup,
        [Parameter(Mandatory = $true)]
        [int]$ImportType,
        [Parameter(Mandatory = $true)]
        [int]$UsernamePattern,

        # Provisioning target: 'ActiveDirectory' (default) or 'EntraID'
        [ValidateSet('ActiveDirectory', 'EntraID')]
        [string]$Mode = 'ActiveDirectory',

        # AD-only parameters (required when Mode = 'ActiveDirectory')
        [string]$UserOU,
        [string]$ClassOU,
        [bool]$CleanGroupMembershipOnlyFromClassOU = $true,
        [string]$GroupDomain = $Domain,

        # Entra ID-only parameters (required when Mode = 'EntraID')
        # App registration ID used to construct the custom directory extension attribute name:
        # extension_<AppId_without_hyphens>_skolniLoginHash
        [string]$ExtensionAttributeAppId,

        # Common parameters
        # AD: attribute used to store the SLHash (default: msDS-cloudExtensionAttribute1).
        # EntraID: fallback onPremisesExtensionAttributes field name for users previously synced from AD.
        [string]$ExtensionAttributeName = "msDS-cloudExtensionAttribute1",
        [bool]$CleanGroupMembership = $false,
        [string[]]$IgnoreGroups = @(),
        [int]$DisplayNamePattern = 1
    )

    # Validate mode-specific required parameters
    if ($Mode -eq 'ActiveDirectory') {
        if ([string]::IsNullOrEmpty($UserOU)) {
            throw "Parameter -UserOU is required when Mode is 'ActiveDirectory'."
        }
        if ([string]::IsNullOrEmpty($ClassOU)) {
            throw "Parameter -ClassOU is required when Mode is 'ActiveDirectory'."
        }
    }
    elseif ($Mode -eq 'EntraID') {
        if ([string]::IsNullOrEmpty($ExtensionAttributeAppId)) {
            throw "Parameter -ExtensionAttributeAppId is required when Mode is 'EntraID'."
        }
        Assert-SkolniLoginMgGraphConnection
        Assert-SkolniLoginExchangeOnlineConnection
    }

    Write-Debug "Loading CSV..."
    $Csv = Import-Csv $FilePath
    Write-Debug "Testing CSV for valid values..."
    Test-SkolniLoginStudentCsv $Csv
    $Csv = $Csv | Select-Object *, Password, Status, Alias, UserPrincipalName

    if ($Mode -eq 'ActiveDirectory') {
        Write-Debug "Loading all AD users..."
        $adUsers = Get-ADUser -SearchBase $UserOU -Filter * -ResultSetSize 5000 -Properties MemberOf

        $adUserGroup = Get-ADGroup $UserGroup

        if ($ImportType -eq 1) {
            Write-Debug "Running initial import (ActiveDirectory)..."
            foreach ($Row in $Csv) {
                $index = $Csv.IndexOf($Row)

                if (-not $PSCmdlet.ShouldProcess("$($Row.GivenName) $($Row.Surname) (Class: $($Row.Class))", "Provision user")) {
                    continue
                }

                $user = New-SkolniLoginUser -User ([ref]$Row) `
                    -Domain $Domain `
                    -Pattern $UsernamePattern `
                    -Path $UserOU `
                    -ExtensionAttributeName $ExtensionAttributeName `
                    -DisplayNamePattern $DisplayNamePattern

                if ($CleanGroupMembership) {
                    $firstMatch = $adUsers | Where-Object { $_.SamAccountName -eq $user.SamAccountName }
                    if ($firstMatch) {
                        if ($CleanGroupMembershipOnlyFromClassOU) {
                            Write-Debug "Removing user $($firstMatch.UserPrincipalName) only from groups in $ClassOU..."
                            $firstMatch.MemberOf | ForEach-Object {
                                $adGroup = Get-ADGroup $_
                                if ($adGroup.DistinguishedName -like "*$ClassOU" -and $IgnoreGroups.IndexOf($adGroup.SamAccountName) -eq -1) {
                                    Write-Debug "Removing user $($firstMatch.UserPrincipalName) from group $($adGroup.SamAccountName)"
                                    Remove-ADGroupMember -Identity $adGroup -Members $user.DistinguishedName -Confirm:$false
                                }
                                else {
                                    Write-Debug "Skipping user $($firstMatch.UserPrincipalName) for removing from group $($adGroup.SamAccountName)"
                                }
                            }
                        }
                        else {
                            Write-Debug "Removing user $($firstMatch.UserPrincipalName) from all groups..."
                            $firstMatch.MemberOf | ForEach-Object {
                                $adGroup = Get-ADGroup $_
                                if ($IgnoreGroups.IndexOf($adGroup.SamAccountName) -eq -1) {
                                    Write-Debug "Removing user $($firstMatch.UserPrincipalName) from group $($adGroup.SamAccountName)"
                                    Remove-ADGroupMember -Identity $adGroup -Members $user.DistinguishedName -Confirm:$false
                                }
                                else {
                                    Write-Debug "Skipping user $($firstMatch.UserPrincipalName) for removing from group $($adGroup.SamAccountName)"
                                }
                            }
                        }
                    }
                }

                Write-Debug "Adding user $($user.UserPrincipalName) to $($adUserGroup.SamAccountName) group"
                Add-ADGroupMember -Identity $adUserGroup -Members $user

                $adUsers = $adUsers | Where-Object { $_.SamAccountName -ne $user.SamAccountName }

                $class = New-SkolniLoginClass -Name $Row.Class `
                    -CurrentYear $CurrentYear `
                    -Domain $GroupDomain `
                    -Path $ClassOU

                Write-Debug "Adding user $($user.UserPrincipalName) to $($class.SamAccountName) class"
                Add-ADGroupMember -Identity $class -Members $user

                $Csv[$index] = $Row
            }

            if ($PSCmdlet.ShouldProcess("$($FilePath)_RESULT.csv", "Write result CSV")) {
                Write-Debug "Storing CSV..."
                $Csv | ConvertTo-Csv -NoTypeInformation | Out-File "$($FilePath)_RESULT.csv"
            }

            Write-Debug "Active Directory users left: $($adUsers.Count)"
            foreach ($leftoverUser in $adUsers) {
                if ($PSCmdlet.ShouldProcess($leftoverUser.UserPrincipalName, "Remove leftover AD user")) {
                    Remove-ADUser -Identity $leftoverUser -Confirm:$false
                }
            }
        }
        elseif ($ImportType -eq 2) {
            Write-Debug "Running update import (ActiveDirectory)..."
            foreach ($Row in $Csv) {
                $index = $Csv.IndexOf($Row)

                if (-not $PSCmdlet.ShouldProcess("$($Row.GivenName) $($Row.Surname) (Class: $($Row.Class))", "Provision user")) {
                    continue
                }

                $user = New-SkolniLoginUser -User ([ref]$Row) `
                    -Domain $Domain `
                    -Pattern $UsernamePattern `
                    -Path $UserOU `
                    -ExtensionAttributeName $ExtensionAttributeName `
                    -DisplayNamePattern $DisplayNamePattern

                Write-Debug "Adding user $($user.UserPrincipalName) to $($adUserGroup.SamAccountName) group"
                Add-ADGroupMember -Identity $adUserGroup -Members $user

                $adUsers = $adUsers | Where-Object { $_.SamAccountName -ne $user.SamAccountName }

                $class = New-SkolniLoginClass -Name $Row.Class `
                    -CurrentYear $CurrentYear `
                    -Domain $GroupDomain `
                    -Path $ClassOU

                Write-Debug "Adding user $($user.UserPrincipalName) to $($class.SamAccountName) class"
                Add-ADGroupMember -Identity $class -Members $user

                $Csv[$index] = $Row
            }

            if ($PSCmdlet.ShouldProcess("$($FilePath)_RESULT.csv", "Write result CSV")) {
                Write-Debug "Storing CSV..."
                $Csv | ConvertTo-Csv -NoTypeInformation | Out-File "$($FilePath)_RESULT.csv"
            }
        }
    }
    elseif ($Mode -eq 'EntraID') {
        Write-Debug "Looking up Entra ID user group '$UserGroup'..."
        $entraUserGroup = Get-MgGroup -Filter "displayName eq '$UserGroup'" -ErrorAction Stop | Select-Object -First 1
        if ($null -eq $entraUserGroup) {
            throw "Entra ID group '$UserGroup' not found. Please create it before running the import."
        }

        if ($ImportType -eq 1) {
            Write-Debug "Running initial import (EntraID)..."

            # Load all current members of the user group to track which users are not in the CSV
            $entraUsers = Get-MgGroupMember -GroupId $entraUserGroup.Id -All |
                Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.user' }

            foreach ($Row in $Csv) {
                $index = $Csv.IndexOf($Row)

                if (-not $PSCmdlet.ShouldProcess("$($Row.GivenName) $($Row.Surname) (Class: $($Row.Class))", "Provision user")) {
                    continue
                }

                $mgUser = New-SkolniLoginEntraUser -User ([ref]$Row) `
                    -Domain $Domain `
                    -Pattern $UsernamePattern `
                    -ExtensionAttributeAppId $ExtensionAttributeAppId `
                    -FallbackExtensionAttributeName $ExtensionAttributeName `
                    -DisplayNamePattern $DisplayNamePattern

                if ($CleanGroupMembership) {
                    Write-Debug "Cleaning class group memberships for $($mgUser.UserPrincipalName)..."
                    $memberOfGroups = Get-MgUserMemberOf -UserId $mgUser.Id -All |
                        Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group' }
                    foreach ($memberOfEntry in $memberOfGroups) {
                        $grp = Get-MgGroup -GroupId $memberOfEntry.Id -Property "id,mailNickname,displayName" -ErrorAction SilentlyContinue
                        if ($null -eq $grp) { continue }
                        if ($grp.MailNickname -match '^\d{4}-' -and $IgnoreGroups -notcontains $grp.MailNickname) {
                            Write-Debug "Removing $($mgUser.UserPrincipalName) from class group $($grp.MailNickname)"
                            Remove-DistributionGroupMember -Identity $grp.MailNickname -Member $mgUser.UserPrincipalName -Confirm:$false -ErrorAction SilentlyContinue
                        }
                        else {
                            Write-Debug "Skipping removal from group $($grp.MailNickname) for $($mgUser.UserPrincipalName)"
                        }
                    }
                }

                Write-Debug "Adding user $($mgUser.UserPrincipalName) to Entra group '$UserGroup'"
                try {
                    New-MgGroupMember -GroupId $entraUserGroup.Id -DirectoryObjectId $mgUser.Id -ErrorAction Stop
                }
                catch {
                    if ($_.Exception.Message -notlike "*already*exist*") { throw }
                    Write-Debug "User $($mgUser.UserPrincipalName) is already a member of '$UserGroup'"
                }

                $entraUsers = $entraUsers | Where-Object { $_.Id -ne $mgUser.Id }

                $class = New-SkolniLoginEntraClass -Name $Row.Class `
                    -CurrentYear $CurrentYear `
                    -Domain $Domain

                Write-Debug "Adding user $($mgUser.UserPrincipalName) to class $($class.MailNickname)"
                Add-SkolniLoginEntraClassMember -Group $class -UserPrincipalName $mgUser.UserPrincipalName

                $Csv[$index] = $Row
            }

            if ($PSCmdlet.ShouldProcess("$($FilePath)_RESULT.csv", "Write result CSV")) {
                Write-Debug "Storing CSV..."
                $Csv | ConvertTo-Csv -NoTypeInformation | Out-File "$($FilePath)_RESULT.csv"
            }

            Write-Debug "Entra ID users left (not in import): $(($entraUsers | Measure-Object).Count)"
            foreach ($member in $entraUsers) {
                $memberUser = Get-MgUser -UserId $member.Id -Property "userPrincipalName,displayName" -ErrorAction SilentlyContinue
                $upn = if ($memberUser) { $memberUser.UserPrincipalName } else { $member.Id }
                Write-Host "User not found in import file: $upn"
                if ($PSCmdlet.ShouldProcess($upn, "Remove leftover Entra user")) {
                    Remove-MgUser -UserId $member.Id -Confirm:$false
                }
            }
        }
        elseif ($ImportType -eq 2) {
            Write-Debug "Running update import (EntraID)..."
            foreach ($Row in $Csv) {
                $index = $Csv.IndexOf($Row)

                if (-not $PSCmdlet.ShouldProcess("$($Row.GivenName) $($Row.Surname) (Class: $($Row.Class))", "Provision user")) {
                    continue
                }

                $mgUser = New-SkolniLoginEntraUser -User ([ref]$Row) `
                    -Domain $Domain `
                    -Pattern $UsernamePattern `
                    -ExtensionAttributeAppId $ExtensionAttributeAppId `
                    -FallbackExtensionAttributeName $ExtensionAttributeName `
                    -DisplayNamePattern $DisplayNamePattern

                Write-Debug "Adding user $($mgUser.UserPrincipalName) to Entra group '$UserGroup'"
                try {
                    New-MgGroupMember -GroupId $entraUserGroup.Id -DirectoryObjectId $mgUser.Id -ErrorAction Stop
                }
                catch {
                    if ($_.Exception.Message -notlike "*already*exist*") { throw }
                    Write-Debug "User $($mgUser.UserPrincipalName) is already a member of '$UserGroup'"
                }

                $class = New-SkolniLoginEntraClass -Name $Row.Class `
                    -CurrentYear $CurrentYear `
                    -Domain $Domain

                Write-Debug "Adding user $($mgUser.UserPrincipalName) to class $($class.MailNickname)"
                Add-SkolniLoginEntraClassMember -Group $class -UserPrincipalName $mgUser.UserPrincipalName

                $Csv[$index] = $Row
            }

            if ($PSCmdlet.ShouldProcess("$($FilePath)_RESULT.csv", "Write result CSV")) {
                Write-Debug "Storing CSV..."
                $Csv | ConvertTo-Csv -NoTypeInformation | Out-File "$($FilePath)_RESULT.csv"
            }
        }
    }
}
function Test-SkolniLoginStudentCsv {
    param (
        $Csv
    )
    
    $ColumnsExpected = @(
        'GivenName',
        'Surname',
        'Class',
        'IDIssuer',
        'IDType',
        'ID'
    )

    $ColumnsOK = $True
    $ColumnsCsv = $Csv | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

    $ColumnsExpected | ForEach-Object {
        If ($ColumnsCsv -notcontains $_) {
            $ColumnsOK = $False
            "Expected column not found: '$($_)'" | Write-Host -ForegroundColor Red
        }
    }

    If (-not $ColumnsOK) {
        Throw "The csv format is incorrect!"
    }

    ## Verify that the contents are OK:
    $ContentOK = $True
    $RowIndex = 0
    ForEach ($Row In $Csv) {
        $RowIndex++
        $Column = 'GivenName'
        if ([string]::IsNullOrEmpty($Row.$Column)) {
            throw "Invalid value for $Column at line $Row, value: $($Row.$Column)"
        }
        $Column = 'Surname'
        if ([string]::IsNullOrEmpty($Row.$Column)) {
            throw "Invalid value for $Column at line $Row, value: $($Row.$Column)"
        }
        $Column = 'Class'
        if ([string]::IsNullOrEmpty($Row.$Column)) {
            throw "Invalid value for $Column at line $Row, value: $($Row.$Column)"
        }
        $Column = 'IDIssuer'
        if (-not ($Row.$Column -eq "CZ" -or $Row.$Column -eq "INT")) {
            throw "Invalid value for $Column at line $Row, value: $($Row.$Column)"
        }
        $Column = 'IDType'
        if (-not ($Row.$Column -eq "BN" -or $Row.$Column -eq "SIN")) {
            throw "Invalid value for $Column at line $Row, value: $($Row.$Column)"
        }
        $Column = 'ID'
        if ([string]::IsNullOrEmpty($Row.$Column)) {
            throw "Invalid value for $Column at line $Row, value: $($Row.$Column)"
        }
    }

    If (-not $ContentOK) {
        Throw "The csv content is incorrect!"
    }
}