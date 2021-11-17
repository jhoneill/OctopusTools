function Edit-OctopusDeploymentProcess      {
    <#
    .SYNOPSIS
        Re-orders and/or removes steps in a project's Deployment Process

    .DESCRIPTION
        Gets the steps in a process and displays a list for the user to choose
        steps. The Deployment process will be set to have those steps (only), and in
        the ordered they are entered. (No step can be entered more than once)

    .PARAMETER Project
        The project whose deployment process is to be edited.

    .PARAMETER Process
        The deployment process to edit

    .PARAMETER InputObject
        A project or process object, normally passed via the pipeline.

    .PARAMETER Apply
        Unless Apply or Force is specified the updated process will be returned for another command to work on.
        If one is specified an update will be triggered

    .PARAMETER Force
        If specified runs the update proces without any confirmation prompts.
        It is a superset of Apply, -Apply -Force does the same as -Force alone.

    .EXAMPLE
    C> Edit-OctopusDeploymentProcess -Project Banana -Apply
    Allows the user to select and re-order the steps in the named project

    .EXAMPLE
    C> Edit-OctopusDeploymentProcess -Project Banana | convertTo-json -Depth 10 | out-file "Short.json"
    Allows the user to select and re-order the steps but this time the new step order is wrriten to
    a file which can be reviewed before applying the update
    #>
    [cmdletbinding(DefaultParameterSetName='ByProjectName',SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,  ParameterSetName='ByProjectName', Position=0 )]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project,

        [Parameter(Mandatory=$true,  ParameterSetName='ByProcess')]
        $Process,

        [Parameter(Mandatory=$true, ParameterSetName='Piped',ValueFromPipeline=$true)]
        $InputObject,

        [switch]$Apply,

        [switch]$Force
    )
    begin   { #check parameters have the right types, and get project's deployment process if need be
        if     ($Process       -and       $Process.pstypenames     -notcontains    'OctopusDeploymentProcess') {
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
        if     ($InputObject   -and -not ($InputObject.pstypenames.where({$_ -in @('OctopusProject', 'OctopusDeploymentProcess')}))) {
                Write-Warning 'Input object is not valid it must be a project or a Deployment process' ; Return
        }
        elseif ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusProject') {
                $Process     = $InputObject.DeploymentProcess()
        }
        elseif ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusDeploymentProcess') {
                $Process = $InputObject
        }
        if     (-not ($Process)) {
            Write-warning "You must supply a project or its process, either as a parameter or via the pipeline" ; return
        }
        #endregion
        $steps = $Process.steps | Select-list -Multiple -Prompt "IDs for step in the order you want them. Use 1..3 for a sequence"
        if ($steps | Group-Object id -NoElement | Where-Object count -gt 1) {
            Write-Warning 'You cannot duplicate a step by adding its number more than once.'
        }
        if     (-not ($Force -or $Apply)) {
            $Process.Steps = $steps
            $Process
        }
        else   {
            $steps | Out-Host
            foreach ($s in $steps) {
                $s.Actions = @($S.Actions | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName')
            }
            $Process.Steps = @($steps     | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName')
            if ($Force -or $PSCmdlet.ShouldProcess($process.ProjectName,'Update Deployment process steps')) {
                Update-OctopusObject $Process -Force
            }
        }
    }
}
