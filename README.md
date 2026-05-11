# SkolniLogin.cz - PowerShell Provisioning
The purpose of this module is to automate provisioning of new accounts into Active Directory and its related systems, or directly into Entra ID (Azure AD) with Exchange Online for mail-enabled security groups.

You can refer here for further information about this problematics: [Best practices for managing students in Active Directory](https://blog.thenetw.org/2018/09/03/best-practices-for-managing-students-in-active-directory/)

## Installing
### PowerShell Gallery
You should use this option to install the latest stable version of this module.
```powershell
Install-Module -Name SkolniLogin
```
You can also update the module:
```powershell
Update-Module -Name SkolniLogin
```
### Manual installation (DEV)
1. Download this repository
1. Import the PowerShell module
```powershell
Import-Module .\SkolniLogin.psm1
```

## Teachers / Employees / Other users
Support will be added in future

## Students

### Active Directory (default mode)
Creating students is the very basic task. All students will be put in the same OU specified as the param. Users will not be moved when being updated.
```powershell
Import-SkolniLoginStudents -FilePath "C:\Users\Administrator\Desktop\students\students.csv" `
    -CurrentYear 2018 `
    -Domain "student.skola.cz" `
    -UserGroup "All Students" `
    -ImportType 1 `
    -UserOU "OU=Students,OU=Users,OU=School,DC=ad,DC=skola,DC=cz" `
    -ClassOU "OU=Classes,OU=Groups,OU=Users,OU=School,DC=ad,DC=skola,DC=cz" `
    -UsernamePattern 1 `
    -CleanGroupMembership $false `
    -CleanGroupMembershipOnlyFromClassOU $true `
    -IgnoreGroups "Domain Users","Wi-Fi Users" `
    -ExtensionAttributeName "msDS-cloudExtensionAttribute1" `
    -GroupDomain "skola.cz" `
    -DisplayNamePattern 1
```

### Entra ID mode (Microsoft Graph + Exchange Online)
You can provision students directly to Entra ID (cloud-only accounts) with class groups created as mail-enabled security groups in Exchange Online. Home Drives and Organizational Units are not supported in this mode.

#### Prerequisites
Install the required PowerShell modules:
```powershell
Install-Module Microsoft.Graph.Users
Install-Module Microsoft.Graph.Groups
Install-Module ExchangeOnlineManagement
```

#### Register a custom directory extension attribute
The module stores the identity hash (SLHash) used for user matching in a custom Entra ID directory extension attribute. You must register this attribute once on an app registration in your tenant:

```powershell
# Connect once as a Global Administrator or Application Administrator
Connect-MgGraph -Scopes "Application.ReadWrite.All"

# Get your app registration (create one if you don't have one for SkolniLogin)
$app = Get-MgApplication -Filter "displayName eq 'SkolniLogin'"

# Register the extension attribute
New-MgApplicationExtensionProperty -ApplicationId $app.Id `
    -Name "skolniLoginHash" `
    -DataType "String" `
    -TargetObjects @("User")

# Note the App ID (not Object ID) of the app registration — you will pass this as -ExtensionAttributeAppId
Write-Host "ExtensionAttributeAppId: $($app.AppId)"
```
The extension attribute will be stored as `extension_<AppId_without_hyphens>_skolniLoginHash` on each user.

#### Authenticate before running the import
```powershell
# Required Graph scopes: User.ReadWrite.All, GroupMember.ReadWrite.All, Directory.ReadWrite.All
Connect-MgGraph -Scopes "User.ReadWrite.All","GroupMember.ReadWrite.All","Directory.ReadWrite.All"

Connect-ExchangeOnline -UserPrincipalName admin@skola.cz
```

#### Run the import
```powershell
Import-SkolniLoginStudents `
    -FilePath "C:\Users\Administrator\Desktop\students\students.csv" `
    -CurrentYear 2024 `
    -Domain "student.skola.cz" `
    -UserGroup "All Students" `
    -ImportType 1 `
    -UsernamePattern 1 `
    -Mode EntraID `
    -ExtensionAttributeAppId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -CleanGroupMembership $false `
    -IgnoreGroups "All Students" `
    -DisplayNamePattern 1
```

#### Migrating from Active Directory to Entra ID
If students were previously provisioned via the AD mode and are now synced to Entra ID, the module will fall back to searching `onPremisesExtensionAttributes` to find existing users. The `ExtensionAttributeName` parameter controls which `onPremisesExtensionAttributes` field is checked (default: `extensionAttribute1`). Verify which Entra attribute your AD sync maps the original AD attribute to and set this parameter accordingly.

```powershell
Import-SkolniLoginStudents ... -Mode EntraID `
    -ExtensionAttributeAppId "..." `
    -ExtensionAttributeName "extensionAttribute1"   # whichever onPremisesExtensionAttribute the SLHash synced to
```

However, the AD attribute (`msDS-cloudExtensionAttribute1`) is **not synced by default** by Azure AD Connect. In that case, use `Sync-SkolniLoginHashToEntra` to copy the hash directly from AD into the custom Entra extension attribute before running the import.

## AD to Entra ID Hash Migration
`Sync-SkolniLoginHashToEntra` is a one-shot utility that reads the SLHash from Active Directory users and writes it to the custom Entra ID directory extension attribute used by the Entra ID provisioning mode. Run this once after enabling Entra ID mode on a tenant where students were previously provisioned via Active Directory.

#### Prerequisites
- ActiveDirectory PowerShell module (`RSAT-AD-PowerShell`)
- Microsoft.Graph.Users module
- An active Graph connection: `Connect-MgGraph -Scopes "User.ReadWrite.All"`

#### Example
```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All"

Sync-SkolniLoginHashToEntra `
    -UserOU "OU=Students,OU=Users,DC=ad,DC=skola,DC=cz" `
    -ExtensionAttributeAppId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

To also overwrite users that already have the attribute set in Entra:
```powershell
Sync-SkolniLoginHashToEntra `
    -UserOU "OU=Students,OU=Users,DC=ad,DC=skola,DC=cz" `
    -ExtensionAttributeAppId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -Force
```

Preview changes without writing anything:
```powershell
Sync-SkolniLoginHashToEntra `
    -UserOU "OU=Students,OU=Users,DC=ad,DC=skola,DC=cz" `
    -ExtensionAttributeAppId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
    -WhatIf
```

#### Parameters
| Parameter | Mandatory | Default | Description |
|---|---|---|---|
| `-UserOU` | Yes | — | AD OU (distinguished name) to search for users |
| `-ExtensionAttributeAppId` | Yes | — | App ID of the app registration where `skolniLoginHash` was registered |
| `-ExtensionAttributeName` | No | `msDS-cloudExtensionAttribute1` | AD attribute holding the SLHash |
| `-Force` | No | false | Overwrite the Entra attribute even if already populated |

After running this cmdlet, the `Import-SkolniLoginStudents` Entra ID mode will find existing students without needing the `onPremisesExtensionAttributes` fallback.

### Classes
The script is also going to create respective classes - mail-enabled security groups.
- **Active Directory mode**: Groups are created as mail-enabled security groups in AD under `-ClassOU`.
- **Entra ID mode**: Groups are created as mail-enabled security groups in Exchange Online (distribution groups of type Security). The `-Domain` parameter is used for the primary SMTP address.

If an existing class (with same ID) is found, it updates its display name to reflect the current year. In AD mode, the e-mail address is also set if missing.

#### Supported class formats
- `1. A` > `2018-A`
- `2.B` > `2017-B`
- `B2A` > `2017-BXA`
- `1A` > `2018-A`

### Parameters
#### -Mode
Provisioning target. `ActiveDirectory` (default) provisions to on-premises AD. `EntraID` provisions directly to Entra ID via Microsoft Graph and Exchange Online.
#### -CurrentYear
The current school year, for example 2018/2019 means the year will be 2018. This is used when creating class identifiers.
#### -Domain
The UPN suffix which you want to use for the students. In Entra ID mode, also used as the domain for class group mail addresses.
#### -UserGroup
The group which all created users will be member of. In AD mode, this is an AD security group. In Entra ID mode, this is an Entra ID security group (looked up by display name).
#### -ImportType
There are currently two imports - Full and New.
##### Full
Value: 1

This is the easiest way - whenever you need to make changes, you use the Full import. Thanks to it, all users will be removed from all groups (except Domain Users), added to their respective groups again. Groups will be renamed to match their current name in the school information system etc. When the student in AD/Entra is not found in the export, you will be prompted to delete the user in the end.
##### New
Value: 2

This allows you to create new students from partial export. None will be removed from their groups, and only new ones will be added.
#### -UserOU (AD only)
The organizational unit under which users should be created.
#### -ClassOU (AD only)
The organizational unit under which class security groups should be created.
#### -UsernamePattern
See Username Patterns section below.
#### -DisplayNamePattern
See Display Name Patterns section below.
#### -ExtensionAttributeAppId (Entra ID mode only)
The App ID (not Object ID) of the app registration used to register the `skolniLoginHash` extension attribute. Required when `-Mode EntraID`.
#### Optional: -CleanGroupMembership
Specifies whether the user should be removed from their existing group memberships before being re-added. Defaults to false.
- **AD mode**: Removes from groups in ClassOU (or all groups if `-CleanGroupMembershipOnlyFromClassOU $false`).
- **Entra ID mode**: Removes from Exchange Online distribution groups whose mail nickname matches the class ID pattern (`YYYY-*`).
#### Optional: -CleanGroupMembershipOnlyFromClassOU (AD only)
User will be removed only from groups in the specified ClassOU. Ignored in Entra ID mode.
#### Optional: -IgnoreGroups
Accepts an array of group names (SamAccountName in AD; mail nickname in Entra ID) which the user should never be removed from.
#### Optional: -ExtensionAttributeName
- **AD mode**: Attribute in Active Directory used to store the SLHash. Defaults to `msDS-cloudExtensionAttribute1`.
- **Entra ID mode**: The `onPremisesExtensionAttributes` field name to check when falling back for previously AD-synced users. Defaults to `extensionAttribute1`.
#### Optional: -GroupDomain (AD only)
The domain under which the class mail addresses should be created. If not specified the value of `-Domain` is used.

## Username Patterns
Currently only a single pattern is available, demonstrated on example: *Jméno Příjmení*

In case the user's name is *First First2 Surname Surname2* only *First* and *Surname2* are used - first part of *GivenName* and last part of *Surname* separated by space.
### Value: 1
1. PrijmeniJme0
1. PrijmeniJme1
1. ...
### Value: 2
1. Jmeno.Prijmeni
1. Jmeno.Prijmeni.1
1. ...
### Value: 3
1. Prijmeni.Jmeno
1. Prijmeni.Jmeno.1
1. ...
### Value: 4
1. JmenoPrijmeni
1. JmenoPrijmeni2
1. ...
### Value: 5
1. PrijmeniJ
1. PrijmeniJ1
1. ...

## DisplayName Patterns
### Value: 1
* Jméno Příjmení
### Value: 2
* Příjmení Jméno
### Value: 3
* Příjmení, Jméno

## User Matching
User's are matched based on their hash which is built followingly:

**IDIssuer**,**IDType**,**SHA1(ID)**

- **Active Directory mode**: The hash is stored in *msDS-cloudExtensionAttribute1* (or the attribute specified by `-ExtensionAttributeName`).
- **Entra ID mode**: The hash is stored in the custom directory extension attribute `extension_<AppId>_skolniLoginHash`. On first run after migration, the module also checks `onPremisesExtensionAttributes` as a fallback.

## Input CSV file
File is basically validated with each import, simply for fields existing and being filled out. The file is CSV and has to have following fields.
### GivenName
### Surname
### Class
### IDIssuer
This is usually the country which issued the ID, either *CZ* or *INT* for ID coming from internal system.
### IDType
User's unique identifier, in the Czech Republic, the birthnumber is used. Values should be *BN*, *SSN* etc.
#### Birth Number
If birth number is specified, it is going to be "sanitized" to format YYYYMMDDXXXX so the `/` will be removed for consistency.
### ID
The ID value itself. Should be ideally only a number, for example *123456000* which is the Czech birth number format.
### Optional: Alias
If the user has some weird name or something, an initial alias can be specified - it will be used during the creation process.

## Output
This script outputs the same values like in the input, however adds the following:
### Password
### UserPrincipalName
Username for logging into Office 365, computers, etc.
### Alias
The alias can be used for logging into computers as well, in case the user's alias is longer than 19 characters (which is the maximum value accepted by Active Directory), their alias will be *user_hash* so they should be using their UPN for logging in instead.

## Home Drives (Active Directory only)
Sets and creates user's Home Drive assigned to a letter. This is mostly for legacy cases, OneDrive for Business should be used instead.
```powershell
Get-ADUser -Filter * | New-SkolniLoginHomeDrive `
    -Path "\\ad.skola.cz\storage\drives\{username}" `
    -Letter "O:" `
    -Force $false
```
The path supports placeholders *username* = *sAMAccountName*, *strippedUpn* which is the username part of the UPN. If user has an existing homedrive, you can override it by using the `Force` parameter. Do not forget to add `:` behind the letter!

The folder is going to automatically inherit permissions so that the user is owner and has full access + the permissions from top folders apply as well. The path sub-tree will be created if the folders don't exist.

If you want to create homedrives per class, you may want to do something like this:
```powershell
$groups = Get-ADGroup -SearchBase "OU=Groups,OU=Uzivatele,DC=ad,DC=skola,DC=cz" -Filter *
foreach($group in $groups) {
    $users = Get-ADGroupMember -Identity $group.Name
    $users | New-SkolniLoginHomeDrive -Path "\\ad.skola.cz\storage\drives\studenti\$($group.Name)\{strippedUpn}" -Letter "O"
}
```

## Append Current Class to Display Name
Useful for adding class information for each user. Only the class with the lowest year for each student is displayed — e.g. if John Doe is a member of 2017-A and 2018-A, only 2017-A is shown as `John Doe (2.A)`. Run this every year to reflect current class changes. If the user's existing display name contains ` (`, the first part is kept as the base and the class suffix is replaced.

### Active Directory
```powershell
$students = Get-ADUser -Filter * -SearchBase "OU=Students,OU=Users,OU=School,DC=ad,DC=skola,DC=cz"
foreach($student in $students) {
    $student | Set-SkolniLoginClassToDisplayName `
        -ClassOU "OU=Classes,OU=Groups,OU=Users,OU=School,DC=ad,DC=skola,DC=cz" `
        -IgnoreGroups "All Students"
}
```

### Entra ID
Class groups are matched by mail nickname pattern (`YYYY-*`), so no `-ClassOU` is needed. Pipe `Get-MgUser` output directly; ensure `-Property "id,displayName,userPrincipalName"` is included.
```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All"

$students = Get-MgUser -Filter "accountEnabled eq true" `
    -Property "id,displayName,userPrincipalName" -All
foreach ($student in $students) {
    $student | Set-SkolniLoginClassToDisplayName `
        -Mode EntraID `
        -IgnoreGroups "all-students"
}
```

## Add UPN into Mail attribute (Active Directory only)
If you are using Group-based licensing, you might have noticed that the primary mail is not provisioned [according to the documentation](https://support.microsoft.com/en-us/help/3190357/how-the-proxyaddresses-attribute-is-populated-in-azure-ad). In order to fix this, you need to populate the `mail` attribute for each user. In order to simply accomplish this, you can run following:
```powershell
$students = Get-ADUser -Filter * -SearchBase "OU=Students,OU=Users,OU=School,DC=ad,DC=skola,DC=cz"
foreach($student in $students) {
    $student | Set-SkolniLoginUpn2Mail
}
```
Please note that any existing value in `mail` attribute will be overwritten. In order to use multiple addresses (for example when changing user's surname in case of marriage and keeping the legacy as well, use `proxyAddresses` attribute).

## Sort users into class organizational units (Active Directory only)
This function will go through all selected students and move them to the respective organizational units per their class. If the OU doesn't exist, it will get automatically created with the class ID (eg. YEAR-TAG)
```powershell
$students = Get-ADUser -Filter * -SearchBase "OU=Students,OU=Users,OU=School,DC=ad,DC=skola,DC=cz"
foreach($student in $students) {
    $student | Set-SkolniLoginOrganizationalUnitByClass `
        -ClassOU "OU=Classes,OU=Groups,OU=Users,OU=School,DC=ad,DC=skola,DC=cz" `
        -IgnoreGroups "All Students" `
        -TargetOU "OU=Students,OU=Users,OU=School,DC=ad,DC=skola,DC=cz"
}
```

## Debugging
In order to see the output of the script, you have to enable debug output first. Errors will be written to stderr like usual.
```powershell
$DebugPreference = "Continue"
```