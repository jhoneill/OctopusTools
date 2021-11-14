function Get-OctopusMachineUsage            {
    <#
      .SYNOPSIS
        Generates a list of projects which use a machine or set of machines.

      .DESCRIPTION
        Finds projects which deploy to [one of] the environment(s) the machine is in, which have at least one step
        which targets a role the machine belongs to, which doesn't exclude those environments, and runbooks which meet the same criteria.

      .PARAMETER Machine
        One or more machines either as objects or the name or ID of a machine.

      .PARAMETER Project
        Narrows the search to a project or set of projects.

      .link
        https://Octopus.com/docs/Octopus-rest-api/examples/deployment-targets/find-target-usage

      .EXAMPLE
            C:> $Get-OctopusMachineUsage test1234
           Checks all projects to see if they use the machine test1234
      .EXAMPLE
            C:> $p = Get-OctopusProjectGroup 'Admin' -Projects
            C:> Get-OctopusMachineUsage test* -Project $p
            Gets the projects in the 'Admin' group, and the checks which of the machines with
            names  starting test "test" are used in which projects
    #>
    [cmdletbinding()]
    param   (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [alias('Name','ID')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Machine,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project = ""
    )
    process{
        if (-not ($Machine.EnvironmentIds -and $Machine.roles)) {$Machine = Get-OctopusMachine $Machine}
        $projects = Get-OctopusProject $Project
        $done = 0
        foreach ($p in $projects) {
            $projEnvironments   =  $p.environments()
            foreach ($m in $Machine) {
                $environments   =  $projEnvironments.where({$_ -in $m.EnvironmentIds})
                Write-Progress -Activity "Seeking steps which match the Environments and roles of $($m.Name)" -Status "Project $($p.name)" -PercentComplete ($done/$projects.count)
                if ($environments -and  (stepsInScope -process $p.DeploymentProcess() -roles $m.Roles -Environments $environments)) {
                    $result = [pscustomobject]@{MachineName=$m.Name;MachineID=$m.Id;ProjectGroup=$p.ProjectGroupName;ProjectName=$p.Name;ProjectID=$p.id;Usage= "Deployment Process"}
                    $result.psTypeNames.add('OctopusMachineUsage')
                    $result
                }
                if ($script:HasRunbooks)     {
                    foreach ($runbook in $p.Runbooks() )  {
                        if     ($runbook.EnvironmentScope -eq 'All')        {$environments = $m.EnvironmentIds}
                        elseif ($runbook.EnvironmentScope -eq 'Specified')  {
                                $environments = $runbook.Environments.where({$_ -in $m.EnvironmentIds})
                        } # otherwise scope "FromProjectLifecycles" amd we have the right ID for that
                        if  ($environments -and (stepsInScope -process (Invoke-OctopusMethod $runbook.Links.RunbookProcesses) -Roles $m.roles -Environments $environments)){
                        $result= [pscustomobject]@{MachineName=$m.Name;MachineID=$m.Id;ProjectGroup=$p.ProjectGroupName;ProjectName=$p.Name;ProjectID=$p.id;Usage="$($Runbook.Name) Runbook"}
                        $result.psTypeNames.add('OctopusMachineUsage')
                        $result
                        }
                    }
                }
            }
            $done += 100
        }
        Write-Progress -Activity "Seeking steps which match the Environments and roles of $($Machine.Name)" -Completed
    }
}
