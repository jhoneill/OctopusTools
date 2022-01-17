function Add-OctopusRelease                 {
    <#
        .SYNOPSIS
            Creates a release from an exsiting project

        .PARAMETER Project
            The Name, ID or Object representing the project

        .PARAMETER ReleaseVersion
            Sets the version number manually. If not specified the command will get the next version number for the project from Octopus

        .PARAMETER ChannelName
            Sets the channel / lifecycle manaually. If not specfied the command will use the first (default) Lifecycle for the project.
            The name can use wildcards, if more than one channel matches the first match will be used

        .PARAMETER Force
             Supresses any confirmation message. By default the command does not prompt for confirmation

        .EXAMPLE
            Add-OctopusRelease -Project 'Enable-Everything'

            Creates a new release for a named project

        .EXAMPLE
            Add-OctopusRelease -Project 'Enable-Everything'  | Add-OctopusDeployment -Environment 'Test'
            Extends the previous example by creating a deployment for the release into the "Test" environment
    #>
    [cmdletbinding(SupportsShouldProcess=$true)]
    param   (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $Project,

        $ReleaseVersion,

        $ChannelName = '*',

        [switch]$Force
    )
    process {
        #https://Octopus.com/docs/Octopus-rest-api/examples/releases/create-release-with-specific-version
        $channel     = Get-OctopusProject -Name $Project -Channels | Where-Object -Property Name -like $ChannelName | Select-Object -First 1
        $releaseBody = @{
            ChannelId        = $channel.Id
            ProjectId        = $channel.ProjectId
            SelectedPackages = @()
        }
        $template    = Invoke-OctopusMethod -EndPoint "deploymentprocesses/deploymentprocess-$($releaseBody.ProjectId)/template?channel=$($releaseBody.ChannelId)"
        if      ($ReleaseVersion)                {
            $releaseBody['Version'] = $ReleaseVersion
        }
        elseif  ($template.NextVersionIncrement) {
            Write-Verbose "Version $($template.NextVersionIncrement) was selected automatically."
            $releaseBody['Version'] = $template.NextVersionIncrement
        }
        elseif  ($template.VersioningPackageStepName) {
            $versioningPackage      = $template.Packages.where({$_.stepname -eq $template.VersioningPackageStepName}) | Select-Object -First 1
            $releaseBody['Version'] = (Get-OctopusPackage $versioningPackage.PackageId).version
            if ($releaseBody['Version'] -eq $versioningPackage.VersionSelectedLastRelease) {
                   Write-Warning -Message "Version $($releaseBody['Version']) was automatically selected from the package '$($versioningPackage.PackageId)'. This has not changed since the last release and may fail."
            }
            else { Write-Verbose -Message "Version $($releaseBody['Version']) was automatically selected from the package '$($versioningPackage.PackageId)'."}
        }
        else    {throw 'A version number was not specified and could not be automatically selected.' }
        foreach ($package in $template.Packages) {
            $endpoint = 'feeds/{0}/packages/versions?packageID={1}&take=1' -f $package.FeedId , $package.PackageId
            $releaseBody.SelectedPackages += @{
                ActionName           = $package.ActionName
                PackageReferenceName = $package.PackageReferenceName
                version              =  (Invoke-OctopusMethod $endpoint -ExpandItems | Select-Object -First 1).version
            }
        }
        if      ($Project.name) {$Project=$Project.name}
        elseif  ($project -isnot [string]) {$Project = $channel.projectID}
        if      ($Force -or $PSCmdlet.ShouldProcess($Project, "Create release, version $($releaseBody.version)")) {
                Invoke-OctopusMethod -PStype OctopusRelease -EndPoint 'releases' -Method POST -Item $releaseBody
        }
    }
}
