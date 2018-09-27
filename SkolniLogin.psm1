. .\src\ImportStudents.ps1
. .\src\ImportUsers.ps1
. .\src\CreateHomeDrives.ps1
. .\src\ClassToDisplayname.ps1

Export-ModuleMember -Function Import-SkolniLoginStudents
Export-ModuleMember -Function Import-SkolniLoginUsers
Export-ModuleMember -Function New-SkolniLoginHomeDrive
Export-ModuleMember -Function Set-SkolniLoginClassToDisplayName