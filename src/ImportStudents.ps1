. .\Users.ps1
. .\Classes.ps1
function Import-SLStudents {
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
        [string[]]$IgnoreGroups
    )
    
    Write-Debug "Loading CSV...";
    $Csv = Import-Csv $FilePath
    Write-Debug "Testing CSV for valid values...";
    Test-SLCsv $Csv
    $Csv = $Csv | Select-Object *,Password,Status,Alias,UserPrincipalName
    Write-Debug "Loading all AD users...";
    $adUsers = Get-ADUser -SearchBase $UserOU -Filter * -ResultSetSize 5000 -Properties MemberOf
    
    $adUserGroup = Get-ADGroup $UserGroup
    
    if($ImportType -eq 1) {
        Write-Debug "Running initial import..."
        foreach($Row in $Csv) {
            $index = $Csv.IndexOf($Row);

            $user = New-SLUser -User ([ref]$Row) `
                -Domain $Domain `
                -Pattern $UsernamePattern `
                -Path $UserOU
            
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

            Write-Debug "Adding user $($user.UserPrincipalName) to $($adUserGroup.SamAccountName) group"
            Add-ADGroupMember -Identity $adUserGroup -Members $user

            $adUsers = $adUsers | Where-Object { $_.SamAccountName -ne $user.SamAccountName };

            $class = New-SLClass -Name $Row.Class `
                -CurrentYear $CurrentYear `
                -Domain $Domain `
                -Path $ClassOU

            Write-Debug "Adding user $($user.UserPrincipalName) to $($class.SamAccountName) class"
            Add-ADGroupMember -Identity $class -Members $user
            
            $Csv[$index] = $Row;
        }

        Write-Debug "Active Directory Users Left"
        foreach($adUser in $adUsers) {
            Write-Host "Delete $($adUser.UserPrincipalName)"
            Remove-ADUSer $adUser -Confirm:$true
        }
        Write-Debug "Storing CSV..."
        $Csv | ConvertTo-Csv -NoTypeInformation | Out-File "$($FilePath)_RESULT.csv"
    }
    elseif ($ImportType -eq 2) {
        Write-Debug "Running update import..."

        foreach ($Row in $Csv) {
            $index = $Csv.IndexOf($Row);

            $user = New-SLStudent -User ([ref]$Row) `
                -Domain $Domain `
                -Pattern $UsernamePattern `
                -Path $UserOU

            Write-Debug "Adding user $($user.UserPrincipalName) to $($adUserGroup.SamAccountName) group"
            Add-ADGroupMember -Identity $adUserGroup -Members $user

            $adUsers = $adUsers | Where-Object { $_.SamAccountName -ne $user.SamAccountName };

            $class = New-SLClass -Name $Row.Class `
                -CurrentYear $CurrentYear `
                -Domain $Domain `
                -Path $ClassOU

            Write-Debug "Adding user $($user.UserPrincipalName) to $($class.SamAccountName) class"
            Add-ADGroupMember -Identity $class -Members $user
            
            $Csv[$index] = $Row;
        }
        
        Write-Debug "Storing CSV..."
        $Csv | ConvertTo-Csv -NoTypeInformation | Out-File "$($FilePath)_RESULT.csv"
    }
}
function Test-SLCsv {
    param (
        $Csv
    )
    
    $ColumnsExpected = @(
        'GivenName',
        'Surname',
        'Class',
        'Country',
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
        $Column = 'Country'
        if (-not ($Row.$Column -eq "CZ")) {
            throw "Invalid value for $Column at line $Row, value: $($Row.$Column)"
        }
        $Column = 'IDType'
        if (-not ($Row.$Column -eq "BN")) {
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

# $DebugPreference = "Continue"
# Import-SLStudents -FilePath "C:\Users\Administrator\Desktop\students\students.csv" `
#     -CurrentYear 2018 `
#     -Domain "spsautocb.cz" `
#     -UserGroup "All Students" `
#     -ImportType 1 `
#     -UserOU "OU=Students,OU=Users,OU=School,DC=ad,DC=spsautocb,DC=cz" `
#     -ClassOU "OU=Classes,OU=Groups,OU=Users,OU=School,DC=ad,DC=spsautocb,DC=cz" `
#     -UsernamePattern 1 `
#     -IgnoreGroups @{}
