function Import-OctopusVariableSetFromXLSX  {
    <#
      .SYNOPSIS
        Imports variables from a .XLSX file which may have more than one destination set, and writes back information about what was done

      .DESCRIPTION
        For a simple CSV file you can use Import-Csv <path> | Set-OctopusVariable -variableSet $set
        This command allows you to take a Excel file from a previous export with columns specifying the set owner,
        and import the variables to whatever destination(s) the file specifies.
        If library variable sets are specified, but don't yet exist they will be created.
        The before and after states of the variable sets will be written back to the excel file.

      .PARAMETER Path
        The path to the .XLSX file

      .PARAMETER WorkSheetName
        The name of the WorkSheet. If no sheet name is specified all sheets which do not end with "-Before" or "-After" will be used.
        Unless NoArtifact is specified, the "before" and after states are written new sheets with those suffixes.

      .PARAMETER LibraryVariableSet
        Specifies a library variable set to update or create - if provided this will over-ride any project or library set in the file

      .PARAMETER Project
        Specifies a project whose variables should be updated - if provided this will over-ride any project or library set in the file

      .PARAMETER NoArtifact
        If specified, prevents writing before and after data back to the .XLSX file

      .PARAMETER  Force
        Will suppress confirmation prompts.

      .PARAMETER ProgressPreference
        Allows the Progress bar act differently in the function, specifying silentlyContinue will suppress it.

#>
    [cmdletbinding(DefaultParameterSetName='Default',SupportsShouldProcess=$true,ConfirmImpact='High')]
    param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        $Path ,

        [Parameter(Position=1)]
        $WorkSheetName  = '*',

        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Library')]
        $LibraryVariableSet,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Project')]
        $Project,

        [switch]$NoArtifact,

        [switch]$Force,

        [ActionPreference]$ProgressPreference = $PSCmdlet.GetVariableValue('ProgressPreference')
    )
    if (-not (Get-command Import-Excel)) {
        throw "To import a .XLSX file you need the importExcel Module ( install-Module importexcel)" ; return
    }
    $excel           = Open-ExcelPackage -Path $Path -ErrorAction stop
    $sheetsProcessed = @()
    foreach ($ws in $excel.Workbook.Worksheets.Where({$_.Name -like $WorkSheetName -and $_.name -notmatch '-Before$|-After$' } )) {
        #keep track of what's imported, and make sure if we do multiple sheets we don't acccidentally re-use a variable set
        $sheetsProcessed += $ws.name
        if ($excel.Workbook.Worksheets.Where({$_.Name -eq ($ws.name + '-Before') } )) {
            $excel.Workbook.Worksheets.Delete(($ws.name + '-Before'))
        }
        if ($excel.Workbook.Worksheets.Where({$_.Name -eq ($ws.name + '-After') } )) {
            $excel.Workbook.Worksheets.Delete(($ws.name + '-After'))
        }
        $VariableSet      = $null
        Write-Progress -Activity "Importing from worksheet $($ws.name)" -Status "Reading data"
        #Import the sheet, ensuring sensitivity is a boolean. To allow one sheet to update multiple things group by the destination and import each group
        $xldata = Import-Excel -ExcelPackage $Excel -WorkSheetName $ws.Name | Where-Object {$null -ne $_.Value} |
            ForEach-Object  {if ($_.isSensitive -is [string]) {$_.isSensitive = $_.isSensitive -eq 'true'} ; $_}
        if (-not ($LibraryVariableSet -or $Project -or $xldata[0].SetOwnerName)) {
            Write-Progress -Activity "Importing from worksheet $($ws.name)" -Completed
            Write-Warning 'If the spreadsheet does not have an owner name for the data you must provide a project or a library variable set.' ; return
        }
        $xldata | Group-Object -Property SetOwnerType, SetOwnerName | ForEach-Object {
                #region Get the variable set, and if we're making an artifact export its 'before' state.
                if      ($LibraryVariableSet -or $Project)                          {$variableSet = Resolve-VariableSet -Project $Project -LibraryVariableSet $LibraryVariableSet}
                elseif  ($_.name -match '^Project')                                 {$variableSet = Get-OctopusProject  -variables -Project $_.group[0].SetOwnerName}
                else                                                                {$variableSet = Get-OctopusLibraryVariableSet -variables -LibraryVariableSet $_.group[0].SetOwnerName}

                if      (-not $variableSet -and $LibraryVariableSet -is [string])   {$variableSet = New-OctopusLibraryVariableSet -Name $LibraryVariableSet}
                elseif  (-not $variableSet -and $_.group[0].SetOwnerName)           {$variableSet = New-OctopusLibraryVariableSet -Name $_.group[0].SetOwnerName}

                if      (-not $variableSet)                                          {throw "Could not get the a variable set from the parameters and data file provided." ; return}
                elseif  (-not $NoArtifact) {
                    Write-Progress -Activity "Importing from worksheet $($ws.name)" -Status "Writing 'before' snapshot for '$($VariableSet.OwnerId)'"
                    $varsbefore = Expand-OctopusVariableSet $VariableSet | Select-Object Id, Name, Type, Scope, IsSensitive, Value
                    $excel      = $varsbefore | Export-excel -WorkSheetName ($ws.name + "-Before") -BoldTopRow -FreezeTopRow -AutoSize -Append -ExcelPackage $excel -PassThru
                }
                #endregion
                Write-Progress -Activity "Importing from worksheet $($ws.name)" -Status "Updating VariableSet for '$($VariableSet.OwnerId)'"
                Write-Verbose "Updating VariableSet '$($VariableSet.ID)' from worksheet '$($ws.name)'"
                $result = $_.group | Set-OctopusVariable -VariableSet $VariableSet -PassThru -Force:$Force -psc $pscmdlet
                if (-not $result) {Write-Warning "--NO UPDATES WERE MADE FOR $($VariableSet.id) --"}
                #region If we're making an artifact export the 'After' state
                if (-not $NoArtifact) {
                    if ($result) {$varsafter =  Expand-OctopusVariableSet $result | Select-Object Id, Name, Type, Scope, IsSensitive, Value }
                    else         {$varsafter = $varsBefore}
                    Write-Progress -Activity "Importing from worksheet $($ws.name)" -Status "Writing 'after' snapshot for '$($VariableSet.OwnerId)'"
                    $excel =      $varsafter | Export-excel -WorkSheetName ($ws.name + "-After" ) -BoldTopRow -FreezeTopRow -AutoSize -Append -ExcelPackage $excel -PassThru
                }
                #endregion
            }
        Write-Progress -Activity "Importing from worksheet $($ws.name)" -Completed
    }
    #Save the Changes we've made to the excel file - compare-worksheet (if run) wants the file to be closed, it will open & compare each before and after, markup changes and save.
    Close-ExcelPackage $excel
    if (-not $NoArtifact) {
        foreach ($wsname in $sheetsProcessed) {
             Write-Progress -Activity "Comparing 'before' and 'after' information." -Status $($ws.name)
             $null = Compare-Worksheet -Referencefile $path -Differencefile $Path  -WorkSheetName "$wsName-Before","$wsName-After" -Key "id" -BackgroundColor lightgreen
        }
        Write-Progress -Activity "Comparing 'before' and 'after' information." -Completed
        if   (Get-Command New-OctopusArtifact -ErrorAction SilentlyContinue ) {New-OctopusArtifact $Path}
    }
}
