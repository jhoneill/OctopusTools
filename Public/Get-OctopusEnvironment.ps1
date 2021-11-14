function Get-OctopusEnvironment             {
<#
    .SYNOPSIS
        Returns Octopus environments, optionally getting their machines or their variables

    .PARAMETER Environment
        One or more environments to return either as names or IDs. Wildcards are accepted, accepts pipeline input,
        if an object is passed, the command will try to use an ID or Name property to find an environment.
        If no Environment is specified, all are returned.

    .PARAMETER Machines
        If specified with -Environment expands the environment's machines

    .EXAMPLE
        C:> Get-OctopusEnvironment *prod*
        Returns all environments with "prod" in the name "Production", "Pre-prod", "Non-Prod" etc.

    .EXAMPLE
        C:> Get-OctopusEnvironment test -machines
        Lists the machines in the test environment.
#>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [ArgumentCompleter([OptopusEnvironmentNamesCompleter])]
        [Parameter(ParameterSetName='Default',   Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Machines',  Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Variables', Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        $Environment,

        [Parameter(ParameterSetName='Machines',  Mandatory=$true  )]
        [switch]$Machines
    )
    process {
        $item = Get-Octopus -Kind Environment -Key $Environment |Sort-Object -Property sortOrder
        if     ($Machines)  {$item.machines() }
        else                {$item }
    }
}
