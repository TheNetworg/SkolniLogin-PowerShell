function Set-SkolniLoginUpn2Mail {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(ValueFromPipeline, Mandatory = $true)]
        $User
    )
    process {
        Write-Debug "Setting UPN to mail field for $($User.sAMAccountName)"

        $upn = $User.UserPrincipalName

        if ($PSCmdlet.ShouldProcess($upn, "Set mail = UPN")) {
            $User | Set-ADUser -Replace @{mail = $upn}
        }
    }
}