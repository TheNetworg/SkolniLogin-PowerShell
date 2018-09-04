function Get-SLClassId {
    param (
        [Parameter(Mandatory = $true)]
        $Name,
        [Parameter(Mandatory = $true)]
        $CurrentYear
    )
    [string]$id = "";
    [string]$separator = "";
    [int]$grade = 0;

    if ($Name -like "*. *") { $separator = ". "; }
    elseif ($Name -like "*.*") { $separator = "."; }
    else { $separator = ""; }

    $Name = $Name.Normalize("FormD") -replace '\p{M}', ''

    $splitted = $Name.Split($separator, [System.StringSplitOptions]::RemoveEmptyEntries);

    $parseResult = [int]::TryParse($splitted[0], [ref]$grade)
    if ($parseResult -eq $true) {
        $year = [int]$CurrentYear - ($grade - 1);

        $id = "$($year)-$($splitted[1])";
    }
    else {
        [System.Collections.ArrayList]$characters = $splitted[0].ToCharArray();

        foreach ($char in $characters) {
            if ([char]::IsDigit($char) -eq $true) {
                $grade = [int]::Parse($char);
                if ($characters.IndexOf($char) -gt 0) {
                    $characters[$characters.IndexOf($char)] = "X";
                }
                else {
                    $characters.RemoveAt(0);
                }
                break;
            }
        }
        $year = [int]$CurrentYear - ($grade - 1);

        $id = "$($year)-$($characters -join '')";
    }
    
    return $id;
}
function New-SLClass {
    param (
        [Parameter(Mandatory = $true)]
        $Name,
        [Parameter(Mandatory = $true)]
        $CurrentYear,
        [Parameter(Mandatory = $true)]
        $Domain,
        [Parameter(Mandatory = $true)]
        $Path
    )

    $group = "";
    $id = Get-SLClassId -Name $name -CurrentYear $CurrentYear;

    try {
        $group = Get-ADGroup $id -Property mail

        Write-Debug "Group $id exists, updating only DisplayName";
        $group | Set-ADGroup -DisplayName $Name

        if ($group.mail) {
            $existingGroupWithSameMail = Get-ADGroup -Filter "mail -eq '$($group.name)@$Domain'"
            if($null -ne $existingGroupWithSameMail) {
                $group | Set-ADGroup -Replace @{mail = "$($group.name)@$Domain"}
            }
        }
    }
    catch {
        Write-Debug "Group doesn't exist yet, will create a new one with id: $id";
        
        $group = New-ADGroup -SamAccountName $id `
            -Name $id `
            -DisplayName $Name `
            -GroupScope Global `
            -GroupCategory Security `
            -OtherAttributes @{'mail' = "$id@$domain"} `
            -Path $Path `
            -PassThru
    }

    return $group;
}
