. ".\src\Users.ps1"
. ".\src\Classes.ps1"

function Import-SkolniLoginStudents {
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
        [string]$UserOU,
        [Parameter(Mandatory = $true)]
        [string]$ClassOU,
        [Parameter(Mandatory = $true)]
        [int]$ImportType,
        [Parameter(Mandatory = $true)]
        [int]$UsernamePattern,
        [string]$ExtensionAttributeName = "msDS-cloudExtensionAttribute1",
        [bool]$CleanGroupMembership = $false,
        [string]$GroupDomain = $Domain,
        [string[]]$IgnoreGroups
    )
    
    Write-Debug "Loading CSV...";
    $Csv = Import-Csv $FilePath
    Write-Debug "Testing CSV for valid values...";
    Test-SkolniLoginCsv $Csv
    $Csv = $Csv | Select-Object *,Password,Status,Alias,UserPrincipalName
    Write-Debug "Loading all AD users...";
    $adUsers = Get-ADUser -SearchBase $UserOU -Filter * -ResultSetSize 5000 -Properties MemberOf
    
    $adUserGroup = Get-ADGroup $UserGroup
    
    if($ImportType -eq 1) {
        Write-Debug "Running initial import..."
        foreach($Row in $Csv) {
            $index = $Csv.IndexOf($Row);

            $user = New-SkolniLoginUser -User ([ref]$Row) `
                -Domain $Domain `
                -Pattern $UsernamePattern `
                -Path $UserOU `
                -ExtensionAttributeName $ExtensionAttributeName
            
            if($CleanGroupMembership) {
                $firstMatch = $adUsers | Where-Object { $_.SamAccountName -eq $user.SamAccountName };
                if ($firstMatch) {
                    Write-Debug "Removing user $($firstMatch.UserPrincipalName) from all groups...";

                    $firstMatch.MemberOf | ForEach-Object {
                        $adGroup = Get-ADGroup $_
                        if ($IgnoreGroups.IndexOf($_.SamAccountName) -eq -1) {
                            Write-Debug "Removing user $($firstMatch.UserPrincipalName) from group $($adGroup.SamAccountName)";
                            Remove-ADGroupMember -Identity $adGroup -Members $_.DistinguishedName -Confirm:$false
                        }
                        else {
                            Write-Debug "Skipping user $($firstMatch.UserPrincipalName) for removing from group $($adGroup.SamAccountName)";
                        }
                    }
                }
            }

            Write-Debug "Adding user $($user.UserPrincipalName) to $($adUserGroup.SamAccountName) group"
            Add-ADGroupMember -Identity $adUserGroup -Members $user

            $adUsers = $adUsers | Where-Object { $_.SamAccountName -ne $user.SamAccountName };

            $class = New-SkolniLoginClass -Name $Row.Class `
                -CurrentYear $CurrentYear `
                -Domain $GroupDomain `
                -Path $ClassOU

            Write-Debug "Adding user $($user.UserPrincipalName) to $($class.SamAccountName) class"
            Add-ADGroupMember -Identity $class -Members $user
            
            $Csv[$index] = $Row;
        }
        
        Write-Debug "Storing CSV..."
        $Csv | ConvertTo-Csv -NoTypeInformation | Out-File "$($FilePath)_RESULT.csv"

        Write-Debug "Active Directory users left: $($adUsers.Count)"
        $adUsers | Remove-ADUSer -Confirm:$true
    }
    elseif ($ImportType -eq 2) {
        Write-Debug "Running update import..."

        foreach ($Row in $Csv) {
            $index = $Csv.IndexOf($Row);

            $user = New-SkolniLoginStudent -User ([ref]$Row) `
                -Domain $Domain `
                -Pattern $UsernamePattern `
                -Path $UserOU

            Write-Debug "Adding user $($user.UserPrincipalName) to $($adUserGroup.SamAccountName) group"
            Add-ADGroupMember -Identity $adUserGroup -Members $user

            $adUsers = $adUsers | Where-Object { $_.SamAccountName -ne $user.SamAccountName };

            $class = New-SkolniLoginClass -Name $Row.Class `
                -CurrentYear $CurrentYear `
                -Domain $GroupDomain `
                -Path $ClassOU

            Write-Debug "Adding user $($user.UserPrincipalName) to $($class.SamAccountName) class"
            Add-ADGroupMember -Identity $class -Members $user
            
            $Csv[$index] = $Row;
        }
        
        Write-Debug "Storing CSV..."
        $Csv | ConvertTo-Csv -NoTypeInformation | Out-File "$($FilePath)_RESULT.csv"
    }
}
function Test-SkolniLoginCsv {
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