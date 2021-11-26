function Add-OctopusDeployment              {
    <#
        .SYNOPSIS
            Adds a Deployment to a release

        .DESCRIPTION
            Each octopus release must be deployed to one or more environments. In the portal a new release is saved, and then "deploy-to" is selected
            This command takes a release and one or more environments and creates the deployments of the release into the

        .PARAMETER Release
            A release object (for example, piped from Add-OctopusRelease or Get-OctopusRelease) or the ID of a release

        .PARAMETER Environment
            The Name(s), ID(s) or Object(s) representing one or more environments to which the release should be deployed
            If no environment is specified, the command will look select all Optional environments in the current phase of the release's lifecycle

        .PARAMETER Force
          Supresses any confirmation message.

        .EXAMPLE
            ps >  Get-OctopusProject "banana" | Add-OctopusRelease | Add-OctopusDeployment -Environment "Test"

            This command creates a new release for project banana and immediately
            deploys it to the environment named "test".   It returns a deployment object which looks like this

            Id              Name            ReleaseID     Environment    TaskID             Created
            --              ----            ------        -----------    ------             -------
            Deployments-789 Deploy to Test  Releases-678  Test           ServerTasks-175007 23/11/2021  14:48

        .EXAMPLE
            ps >  Add-OctopusDeployment -release Releases-678  -Environment "Pre-Prod"

            This command uses the release ID which was displayed in the output of the previous example
            to create an additional deployment. You could also find the release IDs for the project with

            Get-OctopusProject "banana"  -AllReleases
    #>
    [cmdletbinding(SupportsShouldProcess=$true)]
    param   (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
        $Release,

        [ArgumentCompleter([OptopusEnvironmentNamesCompleter])]
        [Parameter(Mandatory=$false, Position=1)]
        $Environment,

        [switch]$Force
    )
    process {
        if      (-not ($Release.ID -and $Release.Version -and ($Release.Links -or $Environment) )) {
                       $Release = Get-OctopusRelease $Release
        }
        if      (-not  $Environment) {
                       $alreadyDone = $release.Deployments() | Select-Object -ExpandProperty environmentid
                       $Environment = $release.Progression() |
                                    Where-Object {-not $_.blocked -and $_.progress -eq 'current' }  |
                                      Select-Object -ExpandProperty OptionalDeploymentTargets |
                                        Where-Object {$_ -notin $alreadyDone}
                        #if we have just selected a bunch of environments, prompt the the user before we deploy into them
                        if ($Environment.count -gt 1) {
                            $local:ConfirmPreference = [System.Management.Automation.ConfirmImpact]::Low
                        }
        }
        foreach ($e in $Environment) {
            if  ($e -is [string])           { $e = Get-OctopusEnvironment $e }
            if  (-not ($e.id -and $e.name)) {throw 'Could not resolve the environment'}

            $deploymentBody = @{ReleaseId = $release.Id; EnvironmentId = $e.id}
            if ($Force -or $PSCmdlet.ShouldProcess($e.name,"Deploy release $($Release.Version) into environment")) {
                Invoke-OctopusMethod -PSType OctopusDeployment -EndPoint deployments -Method POST -Item $deploymentBody
            }
        }
    }
}
