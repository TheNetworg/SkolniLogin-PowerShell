#http://jongurgul.com/blog/get-stringhash-get-filehash/ 
function Get-StringHash([String] $String, $HashName = "SHA1") { 
    $StringBuilder = New-Object System.Text.StringBuilder 
    [System.Security.Cryptography.HashAlgorithm]::Create($HashName).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String))| % { 
        [Void]$StringBuilder.Append($_.ToString("x2")) 
    } 
    $StringBuilder.ToString() 
}

function Get-RandomCharacters($length, $characters) { 
    $random = 1..$length | ForEach-Object { Get-Random -Maximum $characters.length } 
    $private:ofs = "" 
    return [String]$characters[$random]
}

function Assert-SkolniLoginMgGraphConnection {
    $context = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $context) {
        throw "Not connected to Microsoft Graph. Please run 'Connect-MgGraph' before calling this function."
    }
    Write-Debug "Connected to Microsoft Graph as $($context.Account) (tenant: $($context.TenantId))"
}

function Assert-SkolniLoginExchangeOnlineConnection {
    $connections = Get-ConnectionInformation -ErrorAction SilentlyContinue
    if ($null -eq $connections -or ($connections | Measure-Object).Count -eq 0) {
        throw "Not connected to Exchange Online. Please run 'Connect-ExchangeOnline' before calling this function."
    }
    Write-Debug "Connected to Exchange Online (organization: $($connections[0].Organization))"
}