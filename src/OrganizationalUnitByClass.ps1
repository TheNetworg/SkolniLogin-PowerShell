function Set-SkolniLoginOrganizationalUnitByClass {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory = $true)]
        $User,
        [Parameter(Mandatory = $true)]
        [string]$ClassOU,
        [Parameter(Mandatory = $true)]
        [string]$TargetOU,
        [string[]]$IgnoreGroups = @()
    )
    process {
        Write-Debug "Moving $($User.sAMAccountName) to respective class OU"
        
        $adUser = Get-ADUser $User.SamAccountName -Properties "DisplayName", "MemberOf"

        $candidates = New-Object System.Collections.ArrayList

        $adUser.MemberOf | ForEach-Object {
            $adGroup = Get-ADGroup $_ -Properties DisplayName
            if ($adGroup.DistinguishedName -like "*$ClassOU" -and $IgnoreGroups.IndexOf($_.SamAccountName) -eq -1) {
                $candidates.Add($adGroup) | Out-Null;
            }
        }

        $lowest = $null;

        foreach ($group in $candidates) {
            if ($null -eq $lowest) {
                $lowest = $group;
                continue;
            }
            $year = $group.SamAccountName.Split("-")[0]
            $previousYear = $lowest.SamAccountName.Split("-")[0]

            if ($year -lt $previousYear) {
                $lowest = $group;
            }
        }

        if ($lowest -and $null -ne $lowest.DisplayName) {
            Write-Debug "Found class $($lowest.DisplayName) for user $($User.sAMAccountName)"

            $ou = Get-ADOrganizationalUnit -Identity "OU=$($lowest.SamAccountName),$TargetOU"
            if($null -eq $ou) {
                Write-Debug "Organizational unit OU=$($lowest.SamAccountName),$TargetOU not found, creating..."
                $ou = New-ADOrganizationalUnit -Name $lowest.DisplayName -Path $TargetOU
            }

            Write-Debug "Moving user $($User.SamAccountName) to $($ou.DistinguishedName) OU"
            Move-ADObject -Identity $User.sAMAccountName -TargetPath $ou.DistinguishedName
        }
    }
}