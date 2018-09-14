function New-SLHomeDrive {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory = $true)]
        $User,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Letter,
        [bool]$Force = $false
    )
    process {
        Write-Debug "Creating homedrive for $($User.sAMAccountName)"
        
        $adUser = Get-ADUser $User.SamAccountName -Properties "HomeDirectory", "HomeDrive"

        $UserPath = $Path.Replace("{username}", $adUser.sAMAccountName);
        $strippedUpn = $adUser.UserPrincipalName.Split("@")
        $UserPath = $Path.Replace("{strippedUpn}", $strippedUpn[0]);

        if ($adUser.HomeDirectory -and $Force -eq $false) {
            Write-Host "User $($User.sAMAccountName) has homedrive set already. Skipping..."
        }
        else {
            $directory = Get-Item -Path $UserPath -ErrorAction SilentlyContinue
            if ($directory) {
                Write-Host "Directory $UserPath already exists, only adding it to the user's profile."
                if ($adUser.HomeDrive -ne $Letter -and $adUser.HomeDirectory -ne $UserPath) {
                    Set-ADUser -Identity $User.sAMAccountName -Replace @{HomeDirectory = $UserPath; HomeDrive = $Letter}
                }
                else {
                    Write-Debug "User already has correct attributes set. Skipping..."
                }
            }
            else {
                New-Item -ItemType Directory -Path $UserPath

                $Domain = Get-ADDomain

                $UsersAm = "$($Domain.NetBIOSName)\$($User.sAMAccountName)"
                $FileSystemAccessRights = [System.Security.AccessControl.FileSystemRights]::FullControl
                $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::"ContainerInherit", "ObjectInherit"
                $PropagationFlags = [System.Security.AccessControl.PropagationFlags]::None
                $AccessControl = [System.Security.AccessControl.AccessControlType]::Allow 
                $NewAccessrule = New-Object System.Security.AccessControl.FileSystemAccessRule `
                ($UsersAm, $FileSystemAccessRights, $InheritanceFlags, $PropagationFlags, $AccessControl)
        
                $currentACL = Get-ACL -path $UserPath
                $currentACL.SetOwner((New-Object System.Security.Principal.NTAccount($UsersAm)))
                $currentACL.AddAccessRule($NewAccessrule)
                Set-ACL -Path $UserPath -AclObject $currentACL

                Set-ADUser -Identity $User.sAMAccountName -Replace @{HomeDirectory = $UserPath; HomeDrive = $Letter}
            }
        }
    }
}