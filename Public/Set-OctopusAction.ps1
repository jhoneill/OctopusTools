#xxxx todo  * Finish help , TEST select filter to allow step(s) as input / piped actions to skip etc.
function Set-OctopusAction {
    <#
      .SYNOPSIS
        Short description

      .DESCRIPTION
        Long description

      .PARAMETER Action
        Parameter description

     .PARAMETER NewActionName
        If this a string it will be assigned directly as the action name
        If the parameter is a script block it can use the variable $Name to access the existing name of the action
        and what ever the script block returns will become the new new name of the action. A typical script block might be
        {$Name -replace 'ServiceFoo', 'ServiceBar' }

      .PARAMETER NewActionParameters
        A hash table containing Parameter-name / parameter-value pairs. Each time an action is found with
        a property (parameter) name which matches one in the table, its value is updated to the one in the table.

      .PARAMETER RoleReplace
        Two parameters for a -Replace operation to update the machine-role assigned to the step, forexample 'ServiceFoo', 'ServiceBar'

      .PARAMETER ExcludeEnvironmentIDs
        If specified will add environments to the Skip-specific-environments setting or remove them from the "Run-only-for-specified-environments" settting

      .PARAMETER Filter
        One or more scriptblock(s), string(s) or integer(s) representing the where clause(s), name(s), or index(es) to find the desired step(s)

      .EXAMPLE
        An example
    #>
    [cmdletbinding(DefaultParameterSetName='Default')]
    param (
        [Parameter(Position=0,ValueFromPipeline=$true,ParameterSetName='Default',Mandatory=$true)]
        [Alias('Step')]
        $Action,

        [Parameter(ParameterSetName='Project',Mandatory=$true)]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Alias('DeploymentProcess')]
        $Project,

        $NewActionName,
        $NewActionParameters,
        $ExcludeEnvironmentIDs,
        $RoleReplace,
        [ValidateCount(0,1)]
        $Filter
    )
    process {
        #If we have a step get it's actions, if a project, or deployment process came in via the pipeline put the process into  $process for later.
        $process     = $null
        $actionCount = $Action.Count
        if      ($Action.pstypenames  -contains 'OctopusDeploymentStep')    {$Action  = $Action.Actions }
        elseif  ($Action.pstypenames  -contains 'OctopusDeploymentProcess') {$process = $Action }
        elseif  ($Action.DeploymentProcess)                                 {$process = $Action.DeploymentProcess() }

        if      ($Project.pstypenames -contains 'OctopusDeploymentProcess') {$process = $Project }
        elseif  ($Project.DeploymentProcess)                                {$process = $Project.DeploymentProcess() }
        elseif  ($Project) {
                 $process    =  Get-OctopusProject -Project $Project -DeploymentProcess -Verbose:$false
        }
        if      ($process)                                                  {$Action  = $process.Steps.Actions}

        #filter actions. If we got an action as a filter, use its name, if it was a string assume it's a name. Allow where filterscripts as a parameter
        if      ($Filter.Name) {
                 $Action    = $Action | Where-Object {$_.Name -eq   $Filter.Name}
        }
        elseif  ($Filter  -is [string]) {
                 $Action    = $Action | Where-Object {$_.Name -like $Filter}
        }
        elseif  ($Filter  -is [scriptblock]) {
                 $Action    = $Action | Where-Object $Filter
        }
        elseif  ($Filter) {
                Write-Warning "Could not use the the supplied value as a filter"
                return
        }
        if      ($actionCount -ne $Action.Count) {
                Write-Verbose "Selected $($Action.Count) action(s)"
        }

        # loop through the actions if there are many
        foreach ($a in $Action) {
            $name  = $a.name
            if      ($NewActionName -is [string] -and $Action.Count -gt 1) {
                     Write-Warning "Can't use fixed new name '$NewActionName' when there are multiple actions"
                     return
            }
            elseif  ($NewActionName -is [string]) {
                     $a.Name = $NewActionName
            }
            elseif  ($NewActionName -is [scriptblock]) {
                     [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = "Var used in scriptblock passed as param")]
                     $name   = $a.Name  # for use in the script block
                     #re-create the script block otherwise variables from this function are out of scope.
                     $a.name = & ([scriptblock]::create( $NewActionName ))
            }
            if      ($a.name -ne $name) {
                     Write-Verbose ("    New action name: '{0}' - original name was '{1}'." -f $a.name, $name )
            }
            foreach ($k in $NewActionParameters.Keys) {
                if  ($a.properties.$k) {
                     $a.properties.$k = $NewActionParameters.$k
                     Write-verbose ("        {0,-21} set to '{1}'." -f $k,$a.properties.$k )
                }
            }
            if      ($RoleReplace.count -eq 2 -and $a.TargetRoles) {
                     $oldroles            = $a.TargetRoles
                     $a.TargetRoles       = $a.TargetRoles -replace $RoleReplace
                     Write-verbose "        Action target-roles   set to '$($a.TargetRoles)', source was '$oldRoles'."
            }
            if      ($ExcludeEnvironmentIDs) {
                if  ($a.Environments) {
                     $allowedEnvironments = $a.Environments.Where({$a -notin $ExcludeEnvironmentIDs})
                     if (-not $allowedEnvironments) {
                        Write-Verbose "        All the environments are excluded, disabling..."
                        $a.IsDisabled    = $true
                        $a.IsRequired    = $false
                     }
                     else {
                        $a.Environments = @() + $allowedEnvironments
                        Write-Verbose "        Allowed environments  set to $($a.Environments -join ', ')."
                     }
                }
                else {
                        $a.ExcludedEnvironments += $ExcludeEnvironmentIDs
                        Write-Verbose "        Excluded environments set to $( $a.ExcludedEnvironments -join ', ')."
                }
            }
        }
        #if we got a project or process object return the process.
        if ($process) {return $process}
        else          {return $Action}
    }
}