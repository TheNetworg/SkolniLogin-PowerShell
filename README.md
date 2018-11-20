# SkolniLogin.cz - PowerShell Provisioning
The purpose of this module is to automate provisioning of new accounts into Active Directory and its related systems.

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
    -GroupDomain "skola.cz"
```
### Classes
The script is also going to create respective classes - mail-enabled security groups. If an existing class (with same ID) is found - it updates its display name to reflect the current year and also the e-mail address if it is not set and doesn't exist with other group in AD.
#### Supported class formats
- `1. A` > `2018-A`
- `2.B` > `2017-B`
- `B2A` > `2017-BXA`
- `1A` > `2018-A`
### Parameters
#### -CurrentYear
The current school year, for example 2018/2019 means the year will be 2018. This is used when creating class identifiers.
#### -Domain
The UPN suffix which you want to use for the students.
#### -UserGroup
The group which all created users will be member of. The user will be automatically member of *Domain Users*. The aditional group can be used for group-based licensing in Azure AD and so on.
#### -ImportType
There are currently two imports - Full and New.
##### Full
Value: 1

This is the easiest way - whenever you need to make changes, you use the Full import. Thanks to it, all users will be removed from all groups (except Domain Users), added to their respective groups again. Groups will be renamed to match their current name in the school information system etc. When the student in AD is not found in the export, you will be prompted to delete the user in the end.
##### New
Value: 2

This allows you to create new students from partial export. None will be removed from their groups, and only new ones will be added.
#### -UserOU, -ClassOU
The organizational units under which the users and groups should be created.
#### -UsernamePattern
See Username Patterns section below.
#### Optional: -CleanGroupMembership
Specifies whether the user should be removed from their existing group memberships. Defaults to false, and should be used if you want to clean memberships.
#### Optional: -CleanGroupMembershipOnlyFromClassOU
User will be removed only from groups in specified OU. This is good if you want to keep the user in other security groups - for Wi-Fi users etc.
#### Optional: -IgnoreGroups
Accepts an array of *SamAccountNames* of groups which the user should never be removed from when using initial import. This is handy if you have some Wi-Fi access groups in Active Directory or something and want the user to stay in those groups.
#### Optional: -ExtensionAttributeName
Attribute in Active Directory to be used for storing the SLHash. Defaults to `msDS-cloudExtensionAttribute1` for Windows Server 2012+ schema, but for lower schemas, you should use `extensionAttribute1`.
#### Optional: -GroupDomain
The domain under which the class mail addresses should be created under. If not specified the value of `-Domain` parameter is used.

## Username Patterns
Currently only a single pattern is available, demonstrated on example: *Jméno Příjmení*

In case the user's name is *First First2 Surname Surname2* online *First* and *Surname2* are used - first part of *GivenName* and last part of *Surname* separated by space.
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

## User Matching
User's are matched based on their hash which is built followingly:

**IDIssuer**,**IDType**,**SHA1(ID)**

The hash is then stored into *msDS-cloudExtensionAttribute1* in the Active Directory and used for further matching and making changes. This is the reason why it is very crucial to keep the IDIssuer, IDType and ID the same for user in each export.

## Input CSV file
File is basically validated with each import, simply for fields existing and being filled out. The file is CSV and has to have following fields:
### GivenName
### Surname
### Class
### IDIssuer
This is usually the country which issued the ID, either *CZ* or *INT* for ID coming from internal system.
### IDType
User's unique identifier, in the Czech Republic, the birthnumber is used. Values should be *BN*, *SSN* etc.
#### Birth Number
If birth number is specified, it is going  to be "sanitized" to format YYYYMMDDXXXX so the `/` will be removed for consistency.
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

## Home Drives
Sets and creates user's Home Drive assigned to a letter. This is mostly for legacy cases, OneDrive for Business should be used instead.
```powershell
Get-ADUser -Filter * | New-SkolniLoginHomeDrive `
    -Path "\\ad.skola.cz\storage\drives\{username}" `
    -Letter "O" `
    -Force $false
```
The path supports placeholders *username* = *sAMAccountName*, *strippedUpn* which is the username part of the UPN. If user has an existing homedrive, you can override it by using the `Force` parameter.

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
Useful for adding class information for each user:
```powershell
$students = Get-ADUser -Filter * -SearchBase "OU=Students,OU=Users,OU=School,DC=ad,DC=skola,DC=cz"
foreach($student in $students) {
    $student | Set-SkolniLoginClassToDisplayName `
        -ClassOU "OU=Classes,OU=Groups,OU=Users,OU=School,DC=ad,DC=skola,DC=cz" `
        -IgnoreGroups "All Students"
}
```
Only class with the lowest year for each student is displayed, example: if a user John Doe is member of 2017-A and 2018-A, only class 2017-A will be displayed as `John Doe (2.A)`. This command should be run every year to reflect current class changes. If the user has existing display name which contains ` (` the first part will be used as display name and the second will be replaced with the current class.

## Add UPN into Mail attribute
If you are using Group-based licensing, you might have noticed that the primary mail is not provisioned [according to the documentation](https://support.microsoft.com/en-us/help/3190357/how-the-proxyaddresses-attribute-is-populated-in-azure-ad). In order to fix this, you need to populate the `mail` attribute for each user. In order to simply accomplish this, you can run following:
```powershell
$students = Get-ADUser -Filter * -SearchBase "OU=Students,OU=Users,OU=School,DC=ad,DC=skola,DC=cz"
foreach($student in $students) {
    $student | Set-SkolniLoginUpn2Mail
}
```
Please note that any existing value in `mail` attribute will be overwritten. In order to use multiple addresses (for example when changing user's surname in case of marriage and keeping the legacy as well, use `proxyAddresses` attribute).

## Debugging
In order to see the output of the script, you have to enable debug output first. Errors will be written to stderr like usual.
```powershell
$DebugPreference = "Continue"
```