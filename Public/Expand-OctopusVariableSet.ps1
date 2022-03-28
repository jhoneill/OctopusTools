function Expand-OctopusVariableSet          {
    <#
      .SYNOPSIS
        Expands the members of a variable set and optionally displays them on a grid or exports them

      .PARAMETER VariableSet
       The variable set object attached to a library variable set or a project

      .PARAMETER LibraryVariableSet
        When expanding from a library variable set, its name, ID or an object representing it.

      .PARAMETER Project
        When exporting a project, its name ID, or an object representing it.

      .PARAMETER Filter
        If specified returns only variables whose names match the filter (wildcards are supported)

      .PARAMETER Destination
        The path to an XLSx file or CSV file where the expanded variables will be Exported

      .PARAMETER WorksheetName
        When exporting to a .XLSx file the over-rides the default worksheet name (which will be the name of the project, or Library variable set)

      .PARAMETER Append
        When exporting to a .XLSx specifies that the output should be appended to the end of any existing worksheet.

      .PARAMETER GridView
        If Specified displays the variables using PowerShell's Grid view

      .EXAMPLE
        ps >  Expand-OctopusVariableSet -LibraryVariableSet 'Shared Settings' -Destination .\public.csv

       Expands the variables in the named library variable set and exports them to a csv file.

      .EXAMPLE
        Get-OctopusProject 'Banana' -Variables | Expand-OctopusVariableSet -GridView

        Expands the project variables for the named project and displays them in PowerShell's grid view

      .EXAMPLE
        ps >  Get-OctopusLibraryVariableSet | Expand-OctopusVariableSet -Destination .\variable-sets.xlsx

        Gets all the libary variable sets and exports them separate worksheets in in an Excel Workbook.

      .EXAMPLE
        ps > Export-OctopusVariableSet -LibraryVariableSet 'Shared Settings' -Filter https* -Destination .\shared.xlsx

        Uses the alias EXPORT instead of Expand, and exports a single libray variable set, filtered to names that begin https.

      .EXAMPLE
        ps >  Get-OctopusProject Banana,Pineapple -Variables | Export-OctopusVariableSet -Filter https* -Destination ..\shared.xlsx -WorksheetName Projects  -append

        Similar to the previous example, this uses the export alias and filter, but this time takes multiple projects' variable sets
        as input and outputs to a named sheet in an Excel workbook, with each being appened after the previous one.

      .EXAMPLE
       ps > Get-OctopusProject Banana,Pineapple, Mango -Variables | Expand-OctopusVariableSet -filter httpsip* |
                    Select-Object name,value,@{n="scope";e={$_.scope.environment | Convert-OctopusID}}, SetownerName |
                        ConvertTo-CrossTab -RowName -RowName SetOwnerName -ColumnName Scope -ValueName Value | export-excel

        This starts in a similar way to the previous command and selects data that looks like this
        Name         Value         scope         SetOwnerName
        ----         -----         -----         ------------
        HttpsIP      10.1.3.19     Test          Banana
        HttpsIP      10.1.4.19     Production    Banana
        HttpsIP      10.1.3.20     Test          Mango
        HttpsIP      10.1.4.20     Production    Mango
        HttpsIP      10.1.3.21     Test          Pineapple
        HttpsIP      10.1.4.21     Production    Pineapple

        The crosstab operation converts it to:
        SetOwnerName Production Test
        ------------ ---------- ----
        Banana       10.1.4.19  10.1.3.19
        Mango        10.1.4.20  10.1.3.20
        Pineapple    10.1.4.21  10.1.3.21
        And then exports the result to Excel

      .EXAMPLE
            Get-OctopusLibraryVariableSet -LibraryVariableSet 'Shared Settings' -Variables | Expand-OctopusVariableSet -Filter "httpsendpoint*" | where-object {$_.scope.environment.count -eq 1} |
                    select_object Name,Value,@{n="Env";e={Convert-OctopusID $_.scope.environment[0]}}    | ConvertTo-CrossTab -RowName Name -ColumnName env -ValueName Value | export-excel

        Similar to the previous example gets variables named "httpsendpoint*" from shared variables and cross tabs them so that their values for different environments form columnss

        Name                     Production                      Test
        ----                     ---------------                 ----
        HttpsEndPointBanana      https://banana.contoso.com      https://banana.testing.corp.contoso.com
        HttpsEndPointMango       https://mango.contoso.com       https://mango.testing.corp.contoso.com
        HttpsEndPointPineapple   https://pineapple.contoso.com   https://pineapple.testing.corp.contoso.com


    #>
    [Alias('Export-OctopusVariableSet')]
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName='Default')]
    param   (
        [Parameter(Mandatory=$true,Position=0,ParameterSetName='Default',ValueFromPipeline=$true)]
        $VariableSet,

        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Library')]
        $LibraryVariableSet,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Project')]
        $Project,

        $Filter = '*',

        $Destination,

        $WorksheetName,

        [switch]$Append,

        [switch]$GridView
    )
    process {
        $VariableSet = Resolve-VariableSet -Project $Project -LibraryVariableSet $LibraryVariableSet -VariableSet $VariableSet
        if (-not $VariableSet -or $VariableSet.count -gt 1) {throw "Could not get a unique variable set from the parameters provided"; return }

        #id will look like Objects-1234 and the endpoint for Invoke-OctopusMethod will be Objects/Objects-1234 - make that with a regex.
        $OwnerName      = (Invoke-OctopusMethod ($variableset.ownerid  -replace "^(.*)(-\d+)$",'$1/$1$2')).Name
        $ownerType      = $VariableSet.OwnerId -replace '-\d*$'
        $result         = $VariableSet.Variables | Where-Object -Property Name -Like $Filter |
             Add-Member -Force -PassThru -NotePropertyName SetOwnerType      -NotePropertyValue  $ownerType |
             Add-Member -Force -PassThru -NotePropertyName SetOwnerName      -NotePropertyValue  $OwnerName |
                Sort-Object -Property Name, ExpandedScope

        if     ($Destination -is  [scriptblock]) { #re-create the script block otherwise variables from this function are out of scope.
                $destPath = & ([scriptblock]::create( $Destination ))
        }
        elseif ($Destination ) {$destPath = $Destination }

        if     ($destPath -and -not (Test-Path -IsValid -PathType Leaf $destPath)) {
                throw " '$destPath' is a valid filepath."; return
        }
        elseif ($destPath -match    '\.xlsx$' -and (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue ))) {
                throw 'xlsx export requires the import Excel module, which was not found, use Install-Module  importexcel to add it.' ; return
        }
        elseif ($destPath -and $destPath -notmatch '\.xlsx$|\.csv$') {
                throw "Destination needs to be a .csv or .xlsx file."; return
        }
        elseif (($PSBoundParameters.ContainsKey('WorksheetName') -or $Append) -and $destPath -notmatch '\.xlsx$' ) {
                Write-Warning 'WorksheetName and append only apply if destination specifies a .xlsx file.'
        }
        if     ($GridView -and $destPath) {
                Write-Warning 'Gridview is ignored when destination is specified.'
        }
        if     (-not $PSBoundParameters.ContainsKey('WorksheetName') ) {$WorksheetName = $OwnerName}

        if     ($destPath -match '\.csv$') {
                                $result | Select-Object -Property * -ExcludeProperty ID,Scope |  Export-csv -UseQuotes Always -Path $destPath -NoTypeInformation
        }
        elseif ($destPath)     {$result | Export-Excel  -Autosize   -ExcludeProperty ID,Scope -WorksheetName $WorksheetName   -Path $destPath -Append:$Append -TableStyle Medium6 }
        elseif ($GridView)     {$result | Out-GridView  -Title      "Variables in $OwnerName"}
        else                   {$result}
    }
}
