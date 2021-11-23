
function Copy-OctopusProjectStep            {
    <#
      .SYNOPSIS
        Copies a step, either from one Project to another, or duplicating it within the same project

      .DESCRIPTION
        Steps can be complicated, and often the best way to add one to a project is to copy it from somewhere.
        This command can take either projects (as name, ID, or Object), or their deployment process objects
        and source step, and add a copy of the step to the project, updating names, parameters, and applicable environments
        It can make custom alterations specified in a scriptblock paramter

      .PARAMETER Project
        The project whose process is to be updated, this can be the project name, ID or a project object,
        if you have the project object you have the option to use its deployment process in the process parameter instead

      .PARAMETER Process
        An object representing the deployment process to be modified, this can come from a project, or can be a modified process
        for example from a previous call to Copy-OctopusProjectSteps

      .PARAMETER SourceStep
        An object representing the step to be copied into the project

      .PARAMETER InputObject
        When input is piped into the command it can be a project, a process or a step. InputObject is used so the object
        and other parameters can be checked and the piped input assigned to the right parameter. It should not be used from the command line.

      .PARAMETER NewStepName
        The name for the new step. If this a string it will be assigned directly as the step name
        and if there is a single action for the step the same name will be applied to the action.
        If the parameter is a script block it can use the variable $Name to access the existing name of the step and its actions
        and what ever the script block returns will become the new new name of the script / action. A typical script block might be
        {$Name -replace 'ServiceFoo', 'ServiceBar' }

      .PARAMETER NewActionParameters
        A hash table containing Parameter-name / parameter-value pairs. Each time an action is found with
        a property (parameter) name which matches one in the table, its value is updated to the one in the table.

      .PARAMETER RoleReplace
        Two parameters for a -Replace operation to update the machine-role assigned to the step, forexample 'ServiceFoo', 'ServiceBar'

      .PARAMETER UpdateScript
        A script block to change the step being added. If the tthe

      .PARAMETER ExcludeEnvironmentIDs
        If specified will add environments to the Skip-specific-environments setting or remove them from the "Run-only-for-specified-environments" settting

      .PARAMETER Apply
        By default the command returns the updated deployment process but does not send a request to Octopus to apply the changes;
        Apply (and Force) cause the changes to be applied

      .PARAMETER Force
        Supresses any confirmation message. Force is a superset of Apply; so -Apply -Force does the same as -Force alone.


      .EXAMPLE
        ps >$p         = Get-OctopusProject -Name "Test Project 77"
        ps >$newport    = "1001"
        ps >$newservice = "portal"
        ps >$p.DeploymentProcess().steps[0] | Copy-OctopusProjectStep  'Test Project 77' -NewStepName "Add $newService"  -UpdateScript {
        >>            $NewStep.Actions[0].Name = $NewStep.Name; $NewStep.Actions[0].Properties.Port = $newport; $NewStep.Actions[0].Properties.ServiceName =  $newservice
        >>  }

        The first line gets a project and the final line passeses the first step of its deployment process into Copy-OctopusProjectStep.
        In the case, Copy-OctopusProjectStep is modifying the same projct. It sets the name of the copied step
        using a varaible, and uses a script to modifiy only the first action in the step, changing its name, "port" property and "ServiceName" property.

      .EXAMPLE
        ps >$steps = Get-OctopusProject 'enable*Banana' -DeploymentProcess | Select-Object -ExpandProperty steps | Select-List -multiple -Property Name
        ps >Import-Csv Service.csv |ForEach-Object {
        >>      $params = @{
        >>            RoleReplace         = @('Banana.*',$_.TargetRoles)
        >>            NewStepName         = [scriptblock]::Create("`$name -replace 'Banana','$($_.serviceName)'")
        >>            NewActionParameters = @{Port = $_.port; SiteName = $_.SiteName; WhatIf = 'False'}
        >>      }
        >>     $steps  | Copy-OctopusProjectStep @params -Project 'Enable-Everything' -Force
        >>  }

        The first line gets the steps in an existing  deployment process, and uses SELECT-LIST  -Multiple to select a sequence of steps.
        The rest of the example is a loop which repeats for each line in a .csv file
        1 It builds a set of parameters for Copy-OctopusProjectStep which:
          * Sets new action parameters,using values from the csv file
          * Sets new names for the steps by replacing part of their name with a value from the csv
          * Sets a new role with a similar substituation
        2. It then pipes the selected steps into Copy-OctopusProjectStep with these parameters to add them to a project named "Enable-Everything",
        so if the first line selected 4 steps and the second imported 5 sevices the whole process would add 20 steps to "enable-Everything"

    #>
    [cmdletbinding(DefaultParameterSetName='ByProjectName')]
    param (
        [Parameter(Mandatory=$false, ParameterSetName='PipedAndProject',    Position=0 )]
        [Parameter(Mandatory=$true,  ParameterSetName='ByProjectName', Position=0 )]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project,

        [Parameter(Mandatory=$false, ParameterSetName='PipedAndProcess')]
        [Parameter(Mandatory=$true,  ParameterSetName='ByProcess')]
        $Process,

        [Parameter(Mandatory=$false, ParameterSetName='PipedAndStep')]
        [Parameter(Mandatory=$true,  ParameterSetName='ByProjectName',  Position=1)]
        [Parameter(Mandatory=$true,  ParameterSetName='ByProcess',      Position=1)]
        $SourceStep,

        [Parameter(Mandatory=$true, ParameterSetName='PipedAndProject',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true, ParameterSetName='PipedAndProcess',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true, ParameterSetName='PipedAndStep',ValueFromPipeline=$true)]
        $InputObject,

        [Parameter(Position=2)]
        $NewStepName,

        [Parameter(Position=3)]
        [hashtable]$NewActionParameters,

        [Parameter(Position=4)]
        $RoleReplace,

        [Parameter(Position=5)]
        [scriptblock]$UpdateScript,

        [Parameter(Position=6)]
        $ExcludeEnvironmentIDs,

        [switch]$Apply,

        [switch]$Force
    )
    begin   { #check parameters have the right types, and get project's deployment process if need be
        if     ($NewStepName   -and       $NewStepName -isnot [string] -and $NewStepName -isnot [scriptblock]) {
                throw 'The new step name must be a string or a scriptblock'
        }
        if     ($SourceStep    -and       $SourceStep.pstypenames  -notcontains    'OctopusDeploymentStep') {
                 throw 'SourceStep is not valid, it must be a step from an existing process.'
        }
        elseif ($Process       -and       $Process.pstypenames     -notcontains    'OctopusDeploymentProcess') {
                throw 'Process is not valid, it must be an existing deployment process.'
        }
        elseif (-not $Process  -and       $Project.pstypenames     -contains       'OctopusProject' ) {
                     $Process  = $Project.DeploymentProcess()
        }
        elseif ($Project       -and -not  $Process) {
                $Process = Get-OctopusProject -Project $Project -DeploymentProcess
                if (-not $Process) {throw 'Project is not valid, it must be or resolve to an existing project' }
        }
    }
    process {
        #region  figure out what to do with piped input we should get to a process and the step going into it
        $outputAtEnd           = $false  # Have steps been piped in with a single process having multiple updates ?
        if     ($InputObject   -and -not ($InputObject.pstypenames.where({$_ -in @('OctopusProject','OctopusDeploymentStep','OctopusDeploymentProcess')}))) {
                Write-Warning 'Input object is not valid it must be a project, a deployment step, or a Deployment process' ; Return
        }
        elseif ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusProject') {
            if   ($PSBoundParameters.Process -or $PSBoundParameters.Project)  {
                  Write-Warning 'Input object cannot be a project when a project or process is specified' ; Return}
            else {$Process     = $InputObject.DeploymentProcess()}
        }
        elseif ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusDeploymentProcess') {
            if   ($PSBoundParameters.Process -or $PSBoundParameters.Project) {
                  Write-Warning 'Input object cannot be a deployment process when a project or process is specified' ; Return
        }
            else {$Process = $InputObject}
        }
        elseif ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusDeploymentStep') {
            if   ($PSBoundParameters.SourceStep)  {Write-Warning 'Input object cannot be a deployment step when a step parameter is specified' ; Return}
            else {
                  $SourceStep  = $InputObject
                  $outputAtEnd = $true
            }
        }

        if     (-not ($Process -and $SourceStep)) {
            Write-warning "You must supply a project or its process, and a source step either as parameters or via the pipeline" ; return
        }
        #endregion

        #we need to use select and/or $psobject.copy() to avoid changing the original source
        #We also need to remove some of the properties added to actions and steps to make them nicer
        $process.Steps        += $SourceStep  | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName'
        $newStep               = $process.steps[-1]
        if     ($NewStepName -is [string])       { $newStep.Name = $NewStepName}
        elseif ($NewStepName -is [scriptblock])  {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = "Var used in scriptblock passed as param")]
                $name = $newStep.Name  # for use in the script block
                #re-create the script block otherwise variables from this function are out of scope.
                $newstep.name = & ([scriptblock]::create( $NewStepName ))
        }
        Write-Verbose "New step:   '$($newStep.Name)' - source name was '$($SourceStep.Name)''."
        if ($RoleReplace.count -eq 2 -and $newStep.Properties.'Octopus.Action.TargetRoles') {
                $newStep.Properties = $newStep.Properties.psobject.Copy()
                $newStep.Properties.'Octopus.Action.TargetRoles' = $newStep.Properties.'Octopus.Action.TargetRoles'  -replace $RoleReplace
                Write-verbose ("    Step target-roles         set to '{0}', source was '{1}'." -f $newStep.Properties.'Octopus.Action.TargetRoles', $SourceStep.Properties.'Octopus.Action.TargetRoles')
        }

        $newStep.pstypeNames.add('OctopusDeploymentStep')
        $newStep.id            = [guid]::NewGuid().tostring()
        $actionCount           = 0
        $newStep.Actions       = @($SourceStep.Actions  | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName'  )
        $newStep.Actions       | ForEach-Object {
            if ($NewStepName -is [string] -and $newstep.Actions.count -eq 1) {
                $_.Name = $NewStepName
            }
            elseif ($NewStepName -is [string])      {
                Write-Warning "Cannot use '$NewStepName' as the name for multiple actions."
            }
            elseif ($NewStepName -is [scriptblock]) {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = "Var used in scriptblock passed as param")]
                $name = $_.Name  # for use in the script block
                #re-create the script block otherwise variables from this function are out of scope.
                $_.name = & ([scriptblock]::create( $NewStepName ))
            }
            Write-Verbose ("    Action: '{0}' - source name was '{1}'." -f $_.name, $SourceStep.Actions[$actionCount].Name )
            $_.pstypeNames.add('OctopusDeploymentAction')
            $_.id            = [guid]::NewGuid().tostring()
            $_.Properties    =   $SourceStep.Actions[$actionCount].Properties.psobject.Copy()
            $_.Packages      = @($SourceStep.Actions[$actionCount].Packages.foreach({ $_.psobject.Copy() }) )
            foreach ( $p     in  $_.Packages) {
                      $p.id  = [guid]::NewGuid().tostring()
            }
            foreach ($k in $NewActionParameters.Keys) {
                if ($_.properties.$k) {
                    $_.properties.$k = $NewActionParameters.$k
                    Write-verbose ("        {0,-21} set to '{1}'." -f $k,$_.properties.$k )
                }
            }
            if ($RoleReplace.count -eq 2 -and $_.TargetRoles) {
                $_.TargetRoles = $_.TargetRoles -replace $RoleReplace
                Write-verbose "        Action target-roles   set to '$($_.TargetRoles)', source was '$($SourceStep.Actions[$actionCount].TargetRoles)'."
            }
            if ($ExcludeEnvironmentIDs) {
                if ($_.Environments) {
                    $allowedEnvironments = $_.Environments.Where({$_ -notin $ExcludeEnvironmentIDs})
                    if (-not $allowedEnvironments) {
                        Write-Verbose "        All the environments are excluded, disabling..."
                        $_.IsDisabled = $true
                        $_.IsRequired = $false
                    }
                    else {
                        $_.Environments = @() + $allowedEnvironments
                        Write-Verbose "        Allowed environments  set to $($_.Environments -join ', ')."
                    }
                }
                else {
                        $_.ExcludedEnvironments += $ExcludeEnvironmentIDs
                        Write-Verbose "        Excluded environments set to $( $_.ExcludedEnvironments -join ', ')."
                }
            }
            $actionCount ++
        }

        if     ($UpdateScript) { & ([scriptblock]::create( $UpdateScript )) }

        if     (-not ($outputAtEnd -or $Force -or $Apply))   {$Process}
        elseif (-not  $outputAtEnd) {
            $Process.Steps = @($Process.Steps   | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName')
            foreach ($s      in $Process.steps) {
                $s.Actions = @($S.Actions       | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName')
            }
            Update-OctopusObject $Process -Force:$force
        }
        else {  Write-Verbose "Step completed."}
    }
    end {
        if     ($outputAtEnd -and -not ($Force -or $Apply)) {$Process}
        elseif ($outputAtEnd) {
            $Process.Steps = @($Process.Steps   | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName')
            foreach ($s      in $Process.steps) {
                $s.Actions = @($S.Actions       | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName')
            }
            Update-OctopusObject $Process -Force:$force
        }
    }
}
#need equivalent for runbooks
