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

      .PARAMETER Destination
        The path to an XLSx file or CSV file where the expanded variables will be Exported

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

        $Destination,
        [switch]$GridView
    )
    begin   {
        if           ($Destination -and -not (Test-Path -IsValid -PathType Leaf $Destination)) {
                throw " '$Destination' is a valid filepath."
        }
        elseif       ($Destination -match    '\.xlsx$' -and (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue ))) {
                    throw 'xlsx export requires the import Excel module, which was not found, use Install-Module  importexcel to add it.'
        }
        elseif       ($Destination -notmatch '\.xlsx$|\.csv$|') {
                      throw "Destination needs to be a .csv file, or a .xlsx file if the ImportExcel module is installed"
        }
    }
    process {
        $VariableSet = Resolve-VariableSet -Project $Project -LibraryVariableSet $LibraryVariableSet -VariableSet $VariableSet
        if (-not $VariableSet -or $VariableSet.count -gt 1) {throw "Could not get a unique variable set from the parameters provided"; return }

        #id will look like Objects-1234 and the endpoint will be Objects/Objects-1234 make that with a regex.
        $OwnerName      =  (Invoke-OctopusMethod ($variableset.ownerid  -replace "^(.*)(-\d+)$",'$1/$1$2')).name
        $ownerType      = $VariableSet.OwnerId -replace '-\d*$'
        $result = $VariableSet.Variables |
             Add-Member       -PassThru -NotePropertyName SetOwnerType      -NotePropertyValue  $ownerType |
             Add-Member       -PassThru -NotePropertyName SetOwnerName      -NotePropertyValue  $OwnerName |
                Sort-Object Name,ExpandedScope

        if  ($Destination -is  [scriptblock]) { #re-create the script block otherwise variables from this function are out of scope.
                $destPath = & ([scriptblock]::create( $Destination ))
        }
        elseif ($Destination ) {$destPath = $Destination }
        if     ($destPath -match '\.csv$') {
                                $result | Select-Object -Property *    -ExcludeProperty ID,Scope |  Export-csv -UseQuotes Always -Path $destPath -NoTypeInformation
        }
        elseif ($destPath)     {$result | Export-Excel -Path $destPath -ExcludeProperty ID,Scope -WorksheetName $OwnerName -TableStyle Medium6 -Autosize }
        elseif ($GridView)     {$result | Out-GridView -Title           "Variables in $OwnerName"}
        else                   {$result}
    }
}
