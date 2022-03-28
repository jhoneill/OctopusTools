function Get-OctopusLibraryVariableSet      {
<#
.SYNOPSIS
    Return objects representing entries the library's variable sets section, or with the - variables switch the varaible set attached to it

.DESCRIPTION
    Octotpus attaches project-specific variable sets to Projects; the same variable-set objects can have an entry in the
     library's variable set section as a parent. The sets can be expanded with Expand-OctopusVariableSet whether their
     parent is a library entry or a project


.PARAMETER LibraryVariableSet
    The set of interest

.PARAMETER Variables
    Returns the variable set, instead of the library entry.

.EXAMPLE
    C:> Get-OctopusLibraryVariableSet
    Returns the list of variable sets in the library

.EXAMPLE
    C:> Get-OctopusLibraryVariableSet "core" -variables
    Returns the sets of variables in the library with the name "core" in the library

.EXAMPLE
    C:> Get-OctopusLibraryVariableSet "core" -variables  | Expand-OctopusVariableSet
    Follows on from the previous example by expanding the variables in the set showing their values and scopes

#>
    [cmdletbinding(DefaultParameterSetName='Default')]
    param   (
        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [Parameter(ParameterSetName='Default',   Mandatory=$false, Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Variables', Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='GridView',  Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [alias('ID','Name')]
        $LibraryVariableSet,

        [Parameter(ParameterSetName='Variables', Mandatory=$true,  ValueFromPipelineByPropertyName=$true)]
        [Parameter(ParameterSetName='GridView',  Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [switch]$Variables,

        [Parameter(ParameterSetName='GridView',  Mandatory=$true,  ValueFromPipelineByPropertyName=$true)]
        [switch]$GridView,

        [Parameter(DontShow=$true)]
        $VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')
    )

    process {
        #Library variable sets hold things other than variables, so filter down to only things with the right content type.
        if ($LibraryVariableSet) {
            $item = Get-Octopus -Kind LibraryVariableSet -Key $LibraryVariableSet |
                        Where-Object ContentType -eq 'Variables' |
                            Sort-Object -Property name
        }
        else {
            $item = Invoke-OctopusMethod -PSType "OctopusLibraryVariableSet" -EndPoint 'libraryvariablesets?contentType=Variables' -ExpandItems
        }
        if     (-not $item) {return}
        elseif ($GridView)  {$item.Variables().variables | Out-Gridview -Title $item.name}
        elseif ($Variables) {$item.Variables()}
        else                {$item}
    }
}
