function stepsInScope {
    <#
    .DESCRIPTION
        Private / helper function. Given a process (project deployment process or run book process),
        and a set of environments and roles, returns the the steps which apply to those environments and roles.
    #>
    param ($process,  $Roles,$Environments)
    $process.steps.where({                               # Steps which have (one of) the right role(s)  AND ...
           ((-not $Roles) -or ($_.Properties.'Octopus.Action.TargetRoles' -split "\s*,\s*").Where({$Roles -contains $_})) -and
           ((-not $environments) -or $_.Actions.where({
            $exclEnnv = $_.ExcludedEnvironments     #... which apply to all the environments or don't exclude all environments of interest
            (-not ($_.Environments-or $exclEnnv))     -or $Environments.where({$_ -notin $exclEnnv})
        }))
    })
}

function Get-OctopusScopedStep             {
<#
    .SYNOPSIS
        Finds project deployment steps which apply to a particular scope

    .DESCRIPTION
        This command is mainly intened to find project steps which apply to a specific ROLE,
        and within than the scope of the search can be narrowed to only certain projects, or only steps
        which apply to that role in a particular environment, but it can be used just to find steps which
        target a rarely used environment.

    .PARAMETER Role
        The Role(s) of interest

    .PARAMETER Project
        Narrows the scope to a set of projects

    .PARAMETER Environment
        Narrows the scope to one or mmore environments. Can be used without specifying a role, but this may return a large number of steps.

    .EXAMPLE
        C:>Get-OctopusScopedStep database

        Finds steps which use database role

    .EXAMPLE
        C:>Get-OctopusScopedStep -Environment Environments-123

        Finds steps which use the environment with a specific ID. If the environment is widely used this could return every step!

    .EXAMPLE
        C:> $p = Get-OctopusProjectGroup 'Admin' -Projects
        C:> Get-OctopusScopedStep -Role Database -Project $p

        Finds Steps with the database role, but only in projects in the admin group

    .EXAMPLE
        C:> $p = Get-OctopusProjectGroup 'Admin' -Projects
        C:> Get-OctopusScopedStep -Role Database -Project $p

        Finds Steps with the database role, but only in projects in the admin group
#>
    param (
        [ArgumentCompleter([OptopusMachineRolesCompleter])]
        [Parameter(Position=0,ParameterSetName='Role',Mandatory=$true)]
        [Parameter(Position=0,ParameterSetName='Environment',Mandatory=$false)]
        $Role,

        [ArgumentCompleter([OptopusEnvironmentNamesCompleter])]
        [Parameter(Position=1,ParameterSetName='Environment',Mandatory=$true)]
        $Environment ,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Position=2,ValueFromPipeline=$true)]
        $Project = ""

    )
    begin   {
            if ($Environment) {
               $Environments = Get-OctopusEnvironment $Environment | Select-Object -ExpandProperty id
            }
               $projectList = @()
    }
    process {
        if   ($Project.DeploymentProcess -and $Project.name) {
                $projectList += $Project
        }
        else {  $projectList += Get-OctopusProject $Project}
    }
    end    {
        $done    = 0
        $outHash = @{}
        foreach ($p in $projectList) {
            Write-Progress -Activity "Checking Projects for steps which match the Environments and role(s)" -Status "Project $($p.name)" -PercentComplete ($done/$projectList.count)

                if ((-not $Environment) -or    $p.Environments().where({$_ -in $Environments}) ) {
                    stepsInScope -process $p.DeploymentProcess() -roles $Role -Environments $Environments |
                        ForEach-Object {$outHash[$_.id]=$_}
                }
                if ($script:HasRunbooks)     {
                    foreach ($runbook in $p.Runbooks() )  {
                        if ( $runbook.EnvironmentScope -eq 'All' -or (-not $Environment) -or
                            ($runbook.EnvironmentScope -eq 'FromProjectLifecycles' -and
                             $p.Environments().where({$_ -in $Environments}) )     -or
                            ($runbook.EnvironmentScope -eq 'Specified' -and
                             $p.Environments().where({$_ -in $Environments})
                            )
                        ) {
                            stepsInScope -process (Invoke-OctopusMethod $runbook.Links.RunbookProcesses) -Roles $Role  |
                                ForEach-Object {$outHash[$_.id]=$_}
                        }
                    }
                }
            $done += 100
        }
        Write-Progress -Activity "Checking Projects for steps which match the Environments and role(s)" -Completed
        $outhash.Values | Sort-Object -Property ProjectName
    }
}
