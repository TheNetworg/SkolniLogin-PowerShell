function Set-SkolniLoginClassToDisplayName {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory = $true)]
        $User,
        [Parameter(Mandatory = $true)]
        [string]$ClassOU,
        [string[]]$IgnoreGroups = @()
    )
    process {
        Write-Debug "Setting display name for $($User.sAMAccountName)"

        $adUser = Get-ADUser $User.SamAccountName -Properties "DisplayName","MemberOf"

        $candidates = New-Object System.Collections.ArrayList

        $adUser.MemberOf | ForEach-Object {
            $adGroup = Get-ADGroup $_ -Properties DisplayName
            if ($adGroup.DistinguishedName -like "*$ClassOU" -and $IgnoreGroups.IndexOf($_.SamAccountName) -eq -1) {
                $candidates.Add($adGroup) | Out-Null;
            }
        }

        $lowest = $null;

        foreach($group in $candidates) {
            if($null -eq $lowest) {
                $lowest = $group;
                continue;
            }
            $year = $group.SamAccountName.Split("-")[0]
            $previousYear = $lowest.SamAccountName.Split("-")[0]

            if($year -lt $previousYear) {
                $lowest = $group;
            }
        }

        if ($lowest -and $null -ne $lowest.DisplayName) {
            $displayName = $adUser.DisplayName
            try {
                $withoutClass = ($displayName -split " \(")[0]
            }
            catch {
                $withoutClass = $displayName
            }
            Write-Debug "DisplayName set for $($User.sAMAccountName) to $withoutClass ($($lowest.DisplayName))"
            $adUser | Set-ADUser -DisplayName "$withoutClass ($($lowest.DisplayName))"
        }
    }
}