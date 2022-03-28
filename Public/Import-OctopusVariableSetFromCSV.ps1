function Import-OctopusVariableSetFromCSV   {
    <#
      .SYNOPSIS
        Imports variables from a CSV which may have more than one destination set

      .DESCRIPTION
        For a simple CSV file you can use Import-Csv <path> | Set-OctopusVariable -variableSet $set
        This command allows you to take a csv from a previous export with columns specifying the set owner, and
        import the variables to whatever destination(s) the file specifies. If library variable sets are specified,
        but don't yet exist they will be created

      .PARAMETER Path
        The path to the .csv file

      .PARAMETER LibraryVariableSet
        Specifies a library variable set to update or create - if provided this will over-ride any project or library set in the file

      .PARAMETER Project
        Specifies a project whose variables should be updated - if provided this will over-ride any project or library set in the file

      .EXAMPLE
         ps >  Import-OctopusVariableSetFromCSV -Path .\Vars.csv -LibraryVariableSet 'Public' -verbose

         Imports variables to the Library variable set "Public". By specifying verbose the variable to be changed will be shown
         before asking the user whether to commit updates or not.


    #>
    [cmdletbinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        $Path,

        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Library')]
        $LibraryVariableSet,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Project')]
        $Project
    )
    process {
        Import-Csv -Path $Path | ForEach-Object {if ($_.isSensitive -is [string]) {$_.isSensitive = $_.isSensitive -eq 'true'} ; $_}  |
            Group-Object -Property SetId, SetOwnerName  |  ForEach-Object {
                #region Get the variable set
                if      ($LibraryVariableSet -or $Project)                        {$variableSet = Resolve-VariableSet -Project $Project    -LibraryVariableSet $LibraryVariableSet}
                elseif  ($_.name -match '^Project')                               {$variableSet = Get-OctopusProject            -Variables -Project $_.group[0].SetOwnerName}
                elseif  ($_.group[0].SetOwnerName)                                {$variableSet = Get-OctopusLibraryVariableSet -Variables -LibraryVariableSet $_.group[0].SetOwnerName}

                if      (-not $variableSet -and $LibraryVariableSet -is [string]) {$variableSet = New-OctopusLibraryVariableSet -Name $LibraryVariableSet}
                elseif  (-not $variableSet -and $_.group[0].SetOwnerName)         {$variableSet = New-OctopusLibraryVariableSet -Name $_.group[0].SetOwnerName}
                if      (-not $variableSet)                                       {throw "Could not get the a variable set from the parameters and data file provided." ; return}
                Write-Verbose "Updating VariableSet '$($VariableSet.ID)' from '$Path'"
                #endregion
                $_.group | Set-OctopusVariable -VariableSet $VariableSet
            }
    }
}
