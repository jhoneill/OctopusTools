Function Move-OctopusRelease                {
    <#
      .SYNOPSIS
        Promotes a release from one environment to the next

      .DESCRIPTION
        This command is effective "Find the most recent release of project X into environment Y and move it on to environment Z"
        Given a project, it finds the most recent successful release into the "from" enviroment, and starts a deployment of that
        release for the "Into" environment

      .PARAMETER Project
        The name, ID or Project Object for the project of interest. Multiple projects may be passed on the command line or piped into the command

      .PARAMETER From
        The name, ID or Envrinoment object representing the environment to which the project must have been successfully deployed in order to select the release.

      .PARAMETER Into
        The name, ID or Envrinoment object representing the environment to which selected release will be promoted.

      .PARAMETER Force
        Supresses any confirmation message. By default the command does not prompt for confirmation.

      .EXAMPLE
        PS >  Move-OctopusRelease -Project 'Banana' -From 'Dev' -Into 'Test' -Confirm

        There have been 3 releases of project Banana.
        Release 0.0.1 failed to deploy to Dev with release ID 1234
        Release 0.0.2 was deployed to Dev successfully with release ID 222
        Release 0.0.3 was also deployed to Dev successfully with release ID 234

        Release 0.0.3 will be selected as the most recent successful deployment to dev.
        The Confirmation prompt will be

        Are you sure you want to perform this action?
        Performing the operation "Deploy release 0.0.3 into environment 'Test'" on target "Banana".

        Answering Yes will retrun a deployment object which looks similar to this:

        Id             Name              ReleaseID      Environment    TaskID           Created          Task State
        --             ----              ---------      -----------    ------           -------          ----------
        Deployments-456 Deploy to Test   Releases-234   Test          ServerTasks-789  23/11/2021  10:16 Executing

      .LINK
        https://Octopus.com/docs/Octopus-rest-api/examples/releases/promote-release-not-in-destination
    #>
    [cmdletbinding(SupportsShouldProcess=$true)]

    param (
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true, Position=0,ValueFromPipeline=$true)]
        $Project,

        [ArgumentCompleter([OctopusEnvironmentNamesCompleter])]
        [Parameter(Mandatory=$true, Position=1)]
         $From,

        [ArgumentCompleter([OctopusEnvironmentNamesCompleter])]
        [Parameter(Mandatory=$true, Position=2)]
        $Into,

        [switch]$Force
    )
    begin {

        if      ($From.ID -and $From.Name )            {$sourceName = $From.Name;  $From = $From.ID }
        elseif  ($From.Name)                           {$sourceName = $From = $From.Name}
        if      ($From -notmatch '^Environments-\d+$') {
                 $sourceEnv  = Get-OctopusEnvironment -Environment $From
                 $sourceName = $sourceEnv.Name
                 $From       = $sourceEnv.ID
        }

        if      ($Into.ID -and $into.Name)             {$destName  = $Into.Name; $Into = $Into.ID}
        elseif  ($Into.Name)                           {$destName  = $Into = $Into.Name}
        if      ($Into -notmatch '^Environments-\d+$') {
                 $destenv   = Get-OctopusEnvironment -Environment $Into
                 $destName  = $destenv.Name
                 $Into      = $destEnv.Id
        }
    }
    process {
        if      ($Project -is [string])  {$Project = $Project -split "\s*,\s*|\*;\s*"}
        foreach ($p in $Project)  {
            if     ($p.ID -and $p.name  )              {$projName  = $p.Name;  $p = $p.ID}
            elseif ($p.Name)                           {$projName  = $p = $p.Name}
            if     ($p -notmatch '^projects-\d+$')     {
                $proj      = Get-OctopusProject -Project $p
                $projName  = $proj.Name
                $p         = $proj.Id
            }

            $endPointTemplate = "tasks?take=1&environment={0}&project=$p&name=Deploy&States=Success&IncludSystem=false"
            # find the most recent, sucesseful deployment of our project to the source Environment and the associated release. Bail out if we can't find one
            $lastTaskAtSource =      Invoke-OctopusMethod -EndPoint ($endPointTemplate -f $From) -ExpandItems
            if ($lastTaskAtSource) {
                     $rel        =  Invoke-OctopusMethod -EndPoint "deployments/$($lastTaskAtSource.Arguments.DeploymentId)"
                     $releaseId  =  $rel.ReleaseId
                     $releaseVer = (Invoke-OctopusMethod -EndPoint $rel.Links.Release).Version
            }
            if (-not $releaseId)   {
                    Write-Warning "Unable to find a release of $projName which successfully deployed into '$sourceName'"
                    continue
            }

            # if there is no deployment into the destination Environment or it is from a different release, push the release in the source to the destination
            $lastTaskAtDestination = Invoke-OctopusMethod -EndPoint  ($endPointTemplate -f $Into) -ExpandItems
            if (  ( (-not $lastTaskAtDestination )  -or
                     $releaseId -ne ( Invoke-OctopusMethod -EndPoint "deployments/$($lastTaskAtDestination.Arguments.DeploymentId)").ReleaseId
                  ) -and
                  ($Force -or  $pscmdlet.ShouldProcess($projName, "Deploy release $releaseVer into environment '$destName'"))
                ) {
                Invoke-OctopusMethod -PSType OctopusDeployment  -Method "POST" -EndPoint "deployments" -item  @{
                    EnvironmentId            = $Into
                    ReleaseId                = $releaseId
                    ForcePackageDownload     = $false
                    ForcePackageRedeployment = $false
                }
            }
            else {Write-Verbose "Release $releaseVer is deployed to both '$sourceName' and '$destName', no promotion needed."}
        }
    }
}
