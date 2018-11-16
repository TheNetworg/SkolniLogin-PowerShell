function Set-SkolniLoginUpn2Mail {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline, Mandatory = $true)]
        $User
    )
    process {
        Write-Debug "Setting UPN to mail field for $($User.sAMAccountName)"
        
        $upn = $User.UserPrincipalName
 
        $User | Set-ADUser -Replace @{mail = $upn}
    }
}