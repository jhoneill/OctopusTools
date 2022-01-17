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
        ps > $process = Set-OctopusAction -Project 'Banana'  -NewActionParameters @{whatif='True'} -Filter {$_.name -match "DNS"}

        Gets the deployment process for a project, and selects actions with a name containing 'DNS' and
        where they have a "WhatIf" parameter sets its value to true. The Deployment process is output and can be updated with
        Update-Octopus Object.

      .EXAMPLE
        ps > $depProc = Get-OctopusProject 'Banana' -DeploymentProcess
        ps > Set-OctopusAction $depProc.steps[1]    -Disable

        The first command gets a deployment process and the second disables the action(s) in the step
        at index 1 (the index is zero-based so this is the second step). Here variable $depProc is modified AND the all the actions of the step are returned.

      .EXAMPLE
        PS  >  $params = @{
        >>      RoleReplace         = 'Banana*','Bamboo'
        >>      NewActionName       = {$name -replace 'Banana','Bamboo'}
        >>      NewActionParameters = @{PortNumber = 8080 ; WhatIf = 'False'}
        >>    }
        PS  > $process.Steps[1,2] | foreach {$_.name -replace 'Banana','Bamboo'}
        PS  > $process.Steps[1,2] | Set-OctopusAction @params

        These 3 commands update two steps. The final command pipes the steps into Set-OctopusAction, which takes
        RoleReplace, NewActionName, and NewActionParameters from $params updating all the actions they contain.
        The middle command renames the steps. And the first command specifies a RoleReplace parameter to replace
        any role starting "Banana" with the role "Bamboo", a newActionName Parameter to replace any instance of
        "Banana"  in the name with "Bamboo" and NewActionParameters to give any PortNumber parameters a value of "8080"
        and WhatIf parameters a value of "False"
    #>
    [cmdletbinding(DefaultParameterSetName='Default')]
    param (
        [Parameter(Position=0,ValueFromPipeline=$true,ParameterSetName='Default',Mandatory=$true)]
        [Alias('Step')]
        $Action,

        [Parameter(ParameterSetName='Project',Mandatory=$true)]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        [Alias('DeploymentProcess')]
        $Project,

        $NewActionName,
        $NewActionParameters,
        $ExcludeEnvironmentIDs,
        $IncludeEnvironmentIDs,
        $RoleReplace,
        $Filter,
        [switch]$Enable,
        [switch]$Disable,
        [switch]$Required,
        [switch]$NotRequired
    )
    process {
        if (($Required -and $NotRequired) -or ($enable -and $Disable) -or ($ExcludeEnvironmentIDs -and $IncludeEnvironmentIDs)) {
            Write-Warning "Some parameters supplied are mutually exclusive. "
        }
        #If we have a step get it's actions, if a project, or deployment process came in via the pipeline put the process into  $process for later.
        $process     = $null
        $actionCount = $Action.Count
        if      ($Action.pstypenames  -contains 'OctopusProcessStep')    {$Action  = $Action.Actions }
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
                Write-Warning "Could not use the the supplied value as a filter (only one value is supported)"
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
            elseif  ($NewActionName -is [string])      {
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
            else    {Write-Verbose ("    Updating action: '{0}'." -f $a.name, $name )}
            foreach ($k in $NewActionParameters.Keys) {
                if  ($a.properties.$k -and  $NewActionParameters.$k -ne $a.properties.$k ) {
                     $a.properties.$k  =    $NewActionParameters.$k
                     Write-verbose ("        {0,-21} updated to '{1}'." -f $k,$a.properties.$k )
                }
            }
            if      ($RoleReplace.count -eq 2 -and $a.TargetRoles) {
                     $oldroles            = $a.TargetRoles
                     $newroles            = $oldroles      -replace $RoleReplace
                     if ($oldRoles -ne $newroles) {
                           $a.TargetRoles       = $newroles
                           Write-verbose "        Action target-roles   updated to '$($a.TargetRoles)', source was '$oldRoles'."
                     }
                     else {Write-verbose "        Action target-roles   No update required"}
            }
            if      ($Required -and -not $a.ISRequired) {
                        $a.IsRequired = $true
                        Write-verbose ("        {0,-21} updated to '{1}'." -f 'Required',$a.ISRequired )
            }
            elseif  ($a.IsRequired  -and $NotRequired ) {
                        $a.IsRequired = $false
                        Write-verbose ("        {0,-21} updated to '{1}'." -f 'Required',$a.ISRequired )
            }
            if      ($Disable  -and -not $a.IsDisabled) {
                        $a.IsDisabled = $true
                        Write-verbose ("        {0,-21} updated to '{1}'." -f 'IsDisabled',$a.IsDisabled )
            }
            elseif  ($a.IsDisabled -and $Enable )       {
                        $a.IsDisabled = $false
                        Write-verbose ("        {0,-21} updated to '{1}'." -f 'IsDisabled',$a.IsDisabled )
            }
            if      ($ExcludeEnvironmentIDs)  {
                if  ($a.Environments)         {
                     $allowedEnvironments = $a.Environments.Where({$_ -notin $ExcludeEnvironmentIDs})
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
                        $a.ExcludedEnvironments  = @() + ($a.ExcludedEnvironments | Sort-Object -Unique)
                        Write-Verbose "        Excluded environments set to $( $a.ExcludedEnvironments -join ', ')."
                }
            }
            if      ($IncludeEnvironmentIDs)  {
                if  ($a.ExcludedEnvironments) {
                     $a.ExcludedEnvironments = @() + $a.Environments.Where({$_ -notin $IncludeEnvironmentIDs})
                     Write-Verbose "        Disallowed environments  set to $($a.ExcludedEnvironments -join ', ')."
                }
                else {
                        $a.Environments += $IncludeEnvironmentIDs
                        $a.Environments += @() + ($a.Environments  | Sort-Object -Unique)
                        Write-Verbose "        Included environments set to $( $a.Environments -join ', ')."
                }
            }
        }
        #if we got a project or process object return the process.
        if ($process) {return $process}
        else          {return $Action}
    }
}