function Get-OctopusMachine                 {
<#
    .SYNOPSIS
        Returns machines

    .DESCRIPTION
        Can get machines by name or ID and optionally get information about their tasks and
        connection state. Alternatively can get all the machines known to Octopus, or all those
        in specified environments or assigned to specified roles.

    .PARAMETER Machine
        The name or ID of the machine. Wildcards are supported for Machine names, and more than one name
        or ID can be given at the command line or via the pipeline. Names should tab-complete

    .PARAMETER Role
        One or more roles, if specified the command will return machines in the given role(s).
        Can not be used when -Machine is specified, but will combine with -Environment.

    .PARAMETER Environment
        One or more Environments, if specified the command will return machines in the given Environments(s).
        Can not be used when -Machine is specified, but will combine with -Role.

    .PARAMETER First
        If specified, returns the first X machines, the default is 1000

    .PARAMETER Connection
        If specified with -Machine returns the connection state for the specified machine(s).

    .PARAMETER Tasks
        If specified with -Machine returns the tasks for the specified machine(s).
#>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',     Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Connection',  Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Tasks',       Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name','TargetName')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Machine,

        [ArgumentCompleter([OptopusMachineRolesCompleter])]
        [Parameter(ParameterSetName='RoleEnv')]
        $Role,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(ParameterSetName='RoleEnv')]
        $Environment,

        [alias('Take')]
        $First = 1000,

        [Parameter(ParameterSetName='Connection',  Mandatory=$true)]
        [switch]$Connection,

        [Parameter(ParameterSetName='Tasks',       Mandatory=$true)]
        [switch]$Tasks
    )
    process {
        # build a custom endpoint for role / environment if we need one, call Get-Octopus if not
        if      (-not ($Role -or $Environment)) {
                if ($Machine -is [string]) {Write-Verbose "Resolving '$machine' to an Octopus Machine"}
                $item =         Get-Octopus -Kind Machine -Key $machine | Sort-Object -Property name
        }
        else    {
                Write-Verbose "Searching by role '$Role' / environment '$Environment'"
                $endpoint = "machines?take=$First"
                if ($Role) {$endpoint += '&roles=' + ($Role -join ',')}
                if ($Environment) {
                    $endpoint += '&environmentIds=' + ($( foreach ($e in $Environment) {
                        if     ($e.id -and $e.id -match '^environments-\d+$')        {$e.id}
                        elseif ($e -is [string] -and $e -match '^environments-\d+$') {$e}
                        else   {(Get-Octopus  Environment -Key  $e  ).id }
                    }) -join ',')
                }
                $item  =        Invoke-OctopusMethod -PSType OctopusMachine -ExpandItems -EndPoint $endpoint
        }
        if      (-not $item)  {return}
        elseif  ($Connection) {$item | ForEach-Object Connection}
        elseif  ($Tasks)      {$item | ForEach-Object Tasks     }
        else                  {$item }
    }
}
