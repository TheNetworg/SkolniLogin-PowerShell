function Set-SkolniLoginClassToDisplayName {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(ValueFromPipeline, Mandatory = $true)]
        $User,
        # Required for Mode = 'ActiveDirectory'. Not used in Entra ID mode.
        [string]$ClassOU,
        [string[]]$IgnoreGroups = @(),
        [ValidateSet('ActiveDirectory', 'EntraID')]
        [string]$Mode = 'ActiveDirectory'
    )
    begin {
        if ($Mode -eq 'EntraID') {
            Assert-SkolniLoginMgGraphConnection
        }
    }
    process {
        if ($Mode -eq 'ActiveDirectory') {
            if ([string]::IsNullOrEmpty($ClassOU)) {
                throw "Parameter -ClassOU is required when Mode is 'ActiveDirectory'."
            }

            Write-Debug "Setting display name for $($User.sAMAccountName)"

            $adUser = Get-ADUser $User.SamAccountName -Properties "DisplayName","MemberOf"

            $candidates = New-Object System.Collections.ArrayList

            $adUser.MemberOf | ForEach-Object {
                $adGroup = Get-ADGroup $_ -Properties DisplayName
                if ($adGroup.DistinguishedName -like "*$ClassOU" -and $IgnoreGroups.IndexOf($adGroup.SamAccountName) -eq -1) {
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
                if ($PSCmdlet.ShouldProcess($adUser.SamAccountName, "Set DisplayName to '$withoutClass ($($lowest.DisplayName))'")) {
                    $adUser | Set-ADUser -DisplayName "$withoutClass ($($lowest.DisplayName))"
                }
            }
        }
        else {
            # Entra ID mode — uses Microsoft Graph

            # Accept an MgUser object (with Id property) or a UPN string
            if ($User -is [string]) {
                $mgUser = Get-MgUser -UserId $User -Property "id,displayName,userPrincipalName" -ErrorAction Stop
            }
            elseif ($null -ne $User.Id) {
                # MgUser object — re-fetch if DisplayName wasn't retrieved
                if ([string]::IsNullOrEmpty($User.DisplayName)) {
                    $mgUser = Get-MgUser -UserId $User.Id -Property "id,displayName,userPrincipalName" -ErrorAction Stop
                }
                else {
                    $mgUser = $User
                }
            }
            else {
                throw "Entra ID mode requires an MgUser object or a UPN string as pipeline input."
            }

            Write-Debug "Setting display name for $($mgUser.UserPrincipalName)"

            $memberOfIds = Get-MgUserMemberOf -UserId $mgUser.Id -All |
                Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group' } |
                Select-Object -ExpandProperty Id

            $lowest = $null

            foreach ($groupId in $memberOfIds) {
                $grp = Get-MgGroup -GroupId $groupId -Property "id,displayName,mailNickname,mailEnabled" -ErrorAction SilentlyContinue
                if ($null -eq $grp) { continue }
                if ($grp.MailNickname -notmatch '^\d{4}-') { continue }
                if ($IgnoreGroups -contains $grp.MailNickname) { continue }

                if ($null -eq $lowest) {
                    $lowest = $grp
                    continue
                }

                $year = $grp.MailNickname.Split("-")[0]
                $previousYear = $lowest.MailNickname.Split("-")[0]
                if ($year -lt $previousYear) {
                    $lowest = $grp
                }
            }

            if ($null -ne $lowest) {
                $baseDisplayName = ($mgUser.DisplayName -split " \(")[0]
                $newDisplayName = "$baseDisplayName ($($lowest.DisplayName))"
                Write-Debug "DisplayName set for $($mgUser.UserPrincipalName) to $newDisplayName"
                if ($PSCmdlet.ShouldProcess($mgUser.UserPrincipalName, "Set DisplayName to '$newDisplayName'")) {
                    Update-MgUser -UserId $mgUser.Id -DisplayName $newDisplayName
                }
            }
        }
    }
}