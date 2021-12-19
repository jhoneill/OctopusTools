    function Select-OctopusStepAction {
    <#
      .SYNOPSIS
        Selects one or more actions, or the position of  matching actions from a step in a deployment process

      .PARAMETER Step
        The name, ID or the Project object representing the project of interest, or a deployment Process object.

      .PARAMETER Filter
        One or more scriptblock(s), string(s) or integer(s) representing the where clause(s), name(s), or index(es) to find the desired actions(s)

      .PARAMETER First
        If a filter matches more than one item only the first item for that filter is returned.

      .PARAMETER PositionOnly
        Returns the position of the first matching item for the filter instead of the item itself.

      .EXAMPLE
        ps > $iisSteps = Select-OctopusProjectStep $projName -Filter  {$_.actions.actiontype -eq "Octopus.iis"}

        Gets the first step in project "Test 44" which matches Hot

      .EXAMPLE
        ps > Select-OctopusProjectStep 'Test 44' *hot* -positionOnly

        Gets the zero-indexed postion of the first step to match *hot*. Note that when -PostitionOnly is specified, First is assumed.

      .EXAMPLE
        ps > Select-OctopusProjectStep 'Test 44' 1,2,4

        Gets steps at indexes 1,2 and 4 in the deployment process for "test 44" , not that because the index is zero based,
        these are the second, third and fifth steps

      .EXAMPLE
        ps >  $process = Get-OctopusProject -Name "Test Project 77" -DeploymentProcess
        ps >  $steps = Select-OctopusProjectStep $process {$_.actions.properties.serviceName -like '100*'}

        The first command stores the deployment process for a project. The second looks for steps in that process which
        have an action with property (parameter) named "service name" which begins 100
        The filter in the {} is the same as you would write for a where condition

      .EXAMPLE
        ps > Foreach ($s in $Steps) {Select-OctopusProjectStep $process $s -position}

        This takes the the steps returned in the previous example and gets their position.

    #>
    param   (
        [Parameter(Position=0,ValueFromPipeline=$true,Mandatory=$true)]
        $Step,

        [Parameter(Position=1,Mandatory=$true)]
        [Alias('Name','Index')]
        $Filter,

        [switch]$First,

        [switch]$PositionOnly
    )
    process {
        if      ($Step.pstypenames -Notcontains 'OctopusProcessStep') {
                Write-Warning 'The Step parameter must contain a step from a deployment process' ; return}

        foreach ($f in $Filter) {
            if      ($f.Name)         {$f = [scriptblock]::Create(('$_.name -like "{0}"' -f $f.Name )) }
            elseif  ($f -is [string]) {$f = [scriptblock]::Create(('$_.name -like "{0}"' -f $f      )) }
            elseif  ($f -is [System.ValueType] -and ($Step.Actions.count -le $f -or $f -match "^-" -or $f -ne [int]$f)) {
                    Write-Warning "The index for this step's action must be and integer between 0 and $($Step.Actions.count) ; return"
            }

            if     ($f -is [System.ValueType] -and   $PositionOnly) { $f }
            elseif ($f -is [System.ValueType])      {$Step.Actions[$f]}
            elseif ($First -and -not $PositionOnly) {$Step.Actions | Where-Object $f | Select-Object -First 1}
            elseif (            -not $PositionOnly) {$Step.Actions | Where-Object $f }
            else   {
                for ($i = 0; $i -lt $Step.Actions.Count; $i++) {
                    if ($Step.Actions[$i] | Where-Object $f) {$i ; if ($First) {break}  }
                }
            }
        }
    }
}