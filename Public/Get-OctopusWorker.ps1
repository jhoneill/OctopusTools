function Get-OctopusWorker                  {
    <#
    .SYNOPSIS
    Short description

    .DESCRIPTION
    Long description

    .PARAMETER Worker
        Parameter description

    .PARAMETER Connection
        If specified, gets the connection status for the specified worker

    .EXAMPLE
        Get-OctopusWorker 'test-001.corp.contoso.com-worker' -Connection | % logs

        Gets the connection status for a named worker and expands its log information.

    #>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',    Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Connection', Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $Worker,
        [Parameter(ParameterSetName='Connection', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [switch]$Connection
    )
    process {
            $item = Get-Octopus -Kind Worker -key $Worker
            if     (-not $item)  {return}
            elseif ($Connection) {$item.Connection()}
            else                 {$item}
    }
}

