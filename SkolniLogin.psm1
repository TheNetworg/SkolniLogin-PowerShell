. .\src\ImportStudents.ps1
. .\src\ImportUsers.ps1
. .\src\CreateHomeDrives.ps1

Export-ModuleMember -Function Import-SLStudents
Export-ModuleMember -Function Import-SLUsers
Export-ModuleMember -Function New-SLHomeDrive