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
        [string[]]$IgnoreGroups
    )
    
}