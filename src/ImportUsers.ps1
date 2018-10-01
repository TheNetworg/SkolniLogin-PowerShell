function Import-SkolniLoginUsers {
    param (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter(Mandatory = $true)]
        [string]$UserGroup,
        [Parameter(Mandatory = $true)]
        [string]$UserOU,
        [Parameter(Mandatory = $true)]
        [int]$ImportType,
        [Parameter(Mandatory = $true)]
        [int]$UsernamePattern,
        [string]$ExtensionAttributeName = "msDS-cloudExtensionAttribute1",
        [bool]$CleanGroupMembership = $false,
        [string]$GroupDomain = $Domain,
        [string[]]$IgnoreGroups = @()
    )
    
}

function Test-SkolniLoginStudentCsv {
    param (
        $Csv
    )
    
    $ColumnsExpected = @(
        'GivenName',
        'Surname',
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