function Enable-OctopusProjectAction {
    <#
      .SYNOPSIS
        Changes the IsDisabled flag on actions in a project. If called using alias DISABLE actions are disabled, otherwise they are enabled

      .DESCRIPTION
        Enabling or disabling an action (or a single-action step), sets the action's IsDisabledflag.
        This function will take a filter (which can simply) be action name, or can prompt the user to select actions.
        If it is called with its Alias Disable-OctopusProjectAction this function will disable the action(s) selected
        Called iwth its canonical name, Enable-OctopusProjectAction it will enable the action(s).
        It can then either commit the changes or return the deployment process for use in further modifications.
      .PARAMETER Project
        The name, ID or the Project object representing the project of interest, or a deployment Process object.

      .PARAMETER Filter
        One or more scriptblock(s) or string(s) representing the where or name(s) the desired actions(s). If filter is not

      .PARAMETER Apply
        By default the command returns the updated deployment process but does not send a request to Octopus to apply the changes;
        Apply (and Force) cause the changes to be applied

      .PARAMETER Force
        Supresses any confirmation message. Force is a superset of Apply; so -Apply -Force does the same as -Force alone.


      .EXAMPLE
        ps > Disable-OctopusProjectAction -Project 'Test 44' "*Another*"  -Verbose -Apply

        The function is called with its DISABLE alias and an action name.
        Verbose means the actions selected will be displayed before apply prompts to update the deployment process

      .EXAMPLE
        ps > Enable-OctopusProjectAction -Project 'Banana' -Force

        Prompts the user for actions to enable and if any changes are requested they are committed them with no further prompt

      .EXAMPLE
        ps > $DeploymentProcess = disable-OctopusProjectAction  $p   {$_.properties.port -eq "8080"} -Verbose  | Enable-OctopusProjectAction

        This time the Disable version is run to disable steps on the process in $P (or the process of a project in P),
        and it will output an object with scripts which take a "port" parameter disabled if the port is set to 8080
        This object is then piped into the enable version which will prompt the user for steps to be enabled (whether they were disabled by
        the previous step or earlier.)

    #>
    [cmdletBinding()]
    [Alias('Disable-OctopusProjectAction')]
    param   (
        [Parameter(Position=0,ValueFromPipeline=$true,Mandatory=$true)]
        [Alias('Process','DeploymentProcess')]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $Project,

        [Parameter(Position=1)]
        [Alias('Name','Index')]
        $Filter,

        [switch]$Apply,

        [switch]$Force
    )
    begin {
       if      ($MyInvocation.InvocationName -like "E*") {$disable = $false}
       elseif  ($MyInvocation.InvocationName -like "D*") {$disable = $true}
       else    {throw 'Can not tell from the alias if function is enabling or disabling.'}
    }

    process {
        if      ($Project.pstypenames -contains 'OctopusDeploymentProcess') {$process = $Project}
        elseif  ($Project.DeploymentProcess) { $process = $Project.DeploymentProcess() }
        else    {$process = Get-OctopusProject -Project $Project -DeploymentProcess -Verbose:$false}
        if (-not $process) {Write-Warning "Could not get a deployment process from the supplied information" ; return}
        $actionsToUpdate = $false
        if ($filter) {
            foreach ($f in $Filter) {
                if      ($f.Name)         {$f = [scriptblock]::Create(('$_.name -like "{0}"' -f $f.Name )) }
                elseif  ($f -is [string]) {$f = [scriptblock]::Create(('$_.name -like "{0}"' -f $f      )) }

                if ($f -isnot [scriptblock]) {
                        Write-Warning "Could not use the the supplied value as a filter"
                        continue
                }
                else {
                    $process.steps.actions | Where-Object $f | Where-Object {$_.isDisabled -ne $disable } |ForEach-Object {
                        Write-Verbose "Updating Action '$($_.Name)'"
                        $_.isDisabled    = $disable
                        $actionsToUpdate = $true
                    }
                }
            }
        }
        elseif ($disable) {
                  $process.Steps.actions | Select-List -Multiple -Property Name,IsDisabled -Prompt "Which actions would you like to disable (use 2..3 for a range)" |
                     Where-Object {-not $_.isDisabled } |  ForEach-Object {
                            $_.isDisabled    = $true
                            $actionsToUpdate = $true
                    }
        }
        else    {
                  $process.Steps.actions | Select-List -Multiple -Property Name,IsDisabled -Prompt "Which actions would you like to enable (use 2..3 for a range)" |
                    Where-Object {$_.isDisabled } |  ForEach-Object {
                        $_.isDisabled = $false
                        $actionsToUpdate = $true
                    }
        }
        if     (-not ($Force -or $Apply) -or -not $actionsToUpdate ) {$process}
        else   {
                $process.Steps = @($process.Steps   | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName')
                foreach ($s      in $process.steps) {
                    $s.Actions = @($s.Actions       | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName')
                }
                Update-OctopusObject $process -Force:$force
        }
    }
}
