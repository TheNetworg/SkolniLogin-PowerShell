# SkolniLogin.cz - PowerShell Provisioning
The purpose of this module is to automate provisioning of new accounts into Active Directory and its related systems.

## Installing
1. Download this repository
1. Import the PowerShell module
```powershell
Import-Module .\SLPowerShell.psm1
```

## Teachers / Employees / Other users
Support will be added in future

## Students
Creating students is the very basic task. All students will be put in the same OU specified as the param. Users will not be moved when being updated.
```powershell
Import-SLStudents -FilePath "C:\Users\Administrator\Desktop\students\students.csv" `
    -CurrentYear 2018 `
    -Domain "student.skola.cz" `
    -UserGroup "All Students" `
    -ImportType 1 `
    -UserOU "OU=Students,OU=Users,OU=School,DC=ad,DC=skola,DC=cz" `
    -ClassOU "OU=Classes,OU=Groups,OU=Users,OU=School,DC=ad,DC=skola,DC=cz" `
    -UsernamePattern 1 `
    -IgnoreGroups "Domain Users","Wi-Fi Users" `
    -ExtensionAttributeName "msDS-cloudExtensionAttribute1"
```

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
#### Optional: -IgnoreGroups
Accepts an array of *SamAccountNames* of groups which the user should never be removed from when using initial import. This is handy if you have some Wi-Fi access groups in Active Directory or something and want the user to stay in those groups.
#### Optional: -ExtensionAttributeName
Attribute in Active Directory to be used for storing the SLHash. Defaults to `msDS-cloudExtensionAttribute1` for Windows Server 2012+ schema, but for lower schemas, you should use `extensionAttribute1`.

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

## Debugging
In order to see the output of the script, you have to enable debug output first. Errors will be written to stderr like usual.
```powershell
$DebugPreference = "Continue"
```