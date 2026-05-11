function New-SkolniLoginEntraClass {
    param (
        [Parameter(Mandatory = $true)]
        $Name,
        [Parameter(Mandatory = $true)]
        $CurrentYear,
        [Parameter(Mandatory = $true)]
        $Domain
    )

    $id = Get-SkolniLoginClassId -Name $Name -CurrentYear $CurrentYear
    $mailAddress = "$id@$Domain"

    $existingGroup = $null
    try {
        $existingGroup = Get-DistributionGroup -Identity $id -ErrorAction Stop
    }
    catch {
        $existingGroup = $null
    }

    if ($existingGroup) {
        Write-Debug "Exchange Online distribution group '$id' exists, updating DisplayName to '$Name'"
        Set-DistributionGroup -Identity $id -DisplayName $Name

        if ([string]::IsNullOrEmpty($existingGroup.PrimarySmtpAddress)) {
            $conflicting = Get-DistributionGroup -Filter "PrimarySmtpAddress -eq '$mailAddress'" -ErrorAction SilentlyContinue
            if ($null -eq $conflicting) {
                Set-DistributionGroup -Identity $id -PrimarySmtpAddress $mailAddress
            }
        }

        $existingGroup = Get-DistributionGroup -Identity $id
    }
    else {
        Write-Debug "Creating new Exchange Online mail-enabled security group: $id"
        $existingGroup = New-DistributionGroup `
            -Name $id `
            -DisplayName $Name `
            -Alias $id `
            -PrimarySmtpAddress $mailAddress `
            -Type Security
    }

    return [PSCustomObject]@{
        MailNickname       = $id
        DisplayName        = $existingGroup.DisplayName
        PrimarySmtpAddress = $existingGroup.PrimarySmtpAddress
    }
}

function Add-SkolniLoginEntraClassMember {
    param (
        [Parameter(Mandatory = $true)]
        $Group,
        [Parameter(Mandatory = $true)]
        $UserPrincipalName
    )

    try {
        Add-DistributionGroupMember -Identity $Group.MailNickname -Member $UserPrincipalName -ErrorAction Stop
        Write-Debug "Added $UserPrincipalName to distribution group $($Group.MailNickname)"
    }
    catch {
        if ($_.Exception.Message -like "*already*member*" -or $_.Exception.Message -like "*already*exist*") {
            Write-Debug "User $UserPrincipalName is already a member of $($Group.MailNickname)"
        }
        else {
            throw
        }
    }
}
