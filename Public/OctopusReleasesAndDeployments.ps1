function Add-OctopusRelease                 {
    [cmdletbinding(SupportsShouldProcess=$true)]
    param   (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
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

function Get-OctopusRelease                 {
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ValueFromPipeline=$true,Position=0 ,Mandatory=$true)]
        [Alias('ID')]
        $Release,

        [Parameter(ParameterSetName='Artifacts',       Mandatory=$true)]
        [switch]$Artifacts,

        [Parameter(ParameterSetName='Deployments',     Mandatory=$true)]
        [switch]$Deployments,

        [Parameter(ParameterSetName='LifeCycle',       Mandatory=$true)]
        [switch]$LifeCycle,

        [Parameter(ParameterSetName='Phases',          Mandatory=$true)]
        [Alias('Progression')]
        [switch]$Phases,

        [Parameter(ParameterSetName='Project',         Mandatory=$true)]
        [switch]$Project
    )
    process {
        if     ($Release.ReleaseId) {$Release = $Release.ReleaseId}
        elseif ($Release.Id)        {$Release = $Release.Id}
        if ($Release -notmatch '^Releases-\d+$') {
            Write-Warning "'$Release' doesn't look like a valid release: ID it should be in the from releases-12345 "
            return
        }
        $item = Invoke-OctopusMethod -PStype OctopusRelease -EndPoint "releases/$Release"
        if     ($Artifacts)   { $item.Artifacts()   }
        elseif ($Deployments) { $item.Deployments() }
        elseif ($LifeCycle)   { $item.LifeCycle()   }
        elseif ($Phases)      { $item.Progression() }
        elseif ($Project)     { $item.Project()     }
        else                  { $item}
    }
}

Function Move-OctopusRelease {
    #https://Octopus.com/docs/Octopus-rest-api/examples/releases/promote-release-not-in-destination
    param (
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true, Position=0,ValueFromPipeline=$true)]
        $Project,

        [ArgumentCompleter([OptopusEnvironmentNamesCompleter])]
        [Parameter(Mandatory=$true, Position=1)]
         $From,

        [ArgumentCompleter([OptopusEnvironmentNamesCompleter])]
        [Parameter(Mandatory=$true, Position=2)]
        $Into
    )
    begin {
        if      ($From.ID  )                           {$From = $From.ID}
        elseif  ($From.Name)                           {$From = $From.Name}
        if      ($From -notmatch '^Environments-\d+$') {$From = (Get-OctopusEnvironment -Environment $From).Id }

        if      ($Into.ID  )                           {$Into = $Into.ID}
        elseif  ($Into.Name)                           {$Into = $Into.Name}
        if      ($Into -notmatch '^Environments-\d+$') {$Into = (Get-OctopusEnvironment -Environment $Into).Id }
    }
    process {
        if      ($Project -is [string])  {$Project = $Project -split "\s*,\s*|\*;\s*"}
        foreach ($p in $Project)  {
            if     ($p.ID  )                          {$p    = $p.ID}
            elseif ($p.Name)                          {$p    = $p.Name}
            if     ($p -notmatch '^projects-\d+$')    {$p    = (Get-OctopusProject -Project $p).Id }

            $lastTaskEndPoint = "tasks?take=1&environment={0}&project=$p&name=Deploy&States=Success&IncludSystem=false"
            # find the most recent, sucesseful deployment of our project to the source Environment and the associated release. Bail out if we can't find one
            $lastTaskAtSource =      Invoke-OctopusMethod -EndPoint ($lastTaskEndPoint -f $From) -ExpandItems
            if ($lastTaskAtSource) {
                    $releaseId    = (Invoke-OctopusMethod -EndPoint "deployments/$($lastTaskAtSource.Arguments.DeploymentId)").ReleaseId
            }
            if (-not $releaseId)   {
                    Write-Warning "Unable to find a release which successfully deployed into the source environment"
                    continue
            }

            # if there is no deployment into the destination Environment or it is from a different release, push the release in the source to the destination
            $lastTaskAtDestination = Invoke-OctopusMethod -EndPoint  ($lastTaskEndPoint -f $Into) -ExpandItems
            if ((-not $lastTaskAtDestination )  -or
                $releaseId -ne (     Invoke-OctopusMethod -EndPoint "deployments/$($lastTaskAtDestination.Arguments.DeploymentId)").ReleaseId) {
                Invoke-OctopusMethod -PSType OctopusDeployment  -Method "POST" -EndPoint "deployments" -item  @{
                    EnvironmentId            = $Into
                    ReleaseId                = $releaseId
                    ForcePackageDownload     = $false
                    ForcePackageRedeployment = $false
                }
            }
            else {Write-Verbose "The source and destination releases match, not promoting"}
        }
    }
}

function Add-OctopusDeployment              {
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

function Get-OctopusDeployment              {
<#
Get-OctopusDeployment  Deployments-82  -DeploymentProcess | % steps | % actions |  % properties
#>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(Position=0,ValueFromPipeline=$true,   Mandatory=$true)]
        [alias('ID')]
        $Deployment,

        [Parameter(ParameterSetName='Artifacts',         Mandatory=$true)]
        [switch]$Artifacts,

        [Parameter(ParameterSetName='DeploymentProcess', Mandatory=$true)]
        [switch]$Process,

        [Parameter(ParameterSetName='Phases',            Mandatory=$true)]
        [switch]$Phases,

        [Parameter(ParameterSetName='Release',           Mandatory=$true)]
        [switch]$Release,

        [Parameter(ParameterSetName='Task',              Mandatory=$true)]
        [switch]$Task,

        [Parameter(ParameterSetName='Project',           Mandatory=$true)]
        [switch]$Project
    )
    process {
        if     ($Deployment.DeploymentId) {$Deployment = $Deployment.DeploymentId}
        elseif ($Deployment.Id)           {$Deployment = $Deployment.Id}
        if     ($Deployment -notmatch '^Deployments-\d+$') {
            Write-Warning "'$Deployment' doesn't look like a valid Deployment ID it should be in the from Deployments-12345 "
            return
        }
        $item = Invoke-OctopusMethod -PSType OctopusDeployment -EndPoint "deployments/$Deployment"
        if     ($Artifacts){$item.Artifacts()}
        elseif ($Process)  {$item.DeploymentProcess()}
        elseif ($Project)  {$item.Project()}
        elseif ($Release)  {$item.Release() }
        elseif ($Task)     {$item.Task() }
        else               {$item}
    }
}

function Get-OctopusTask                    {
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(Position=0,ValueFromPipeline=$true, Mandatory=$true,ParameterSetName='Default')]
        [Parameter(Position=0,ValueFromPipeline=$true, Mandatory=$true,ParameterSetName='Artifacts')]
        [Parameter(Position=0,ValueFromPipeline=$true, Mandatory=$true,ParameterSetName='Details')]
        [Parameter(Position=0,ValueFromPipeline=$true, Mandatory=$true,ParameterSetName='Raw')]
        [Alias('ID')]
        $Task,

        # Queued, , Failed, Canceled, TimedOut, Success, Cancelling

        [Parameter(ParameterSetName='Artifacts',       Mandatory=$true)]
        [switch]$Artifacts,

        [Parameter(ParameterSetName='Details',         Mandatory=$true)]
        [switch]$Details,

        [Parameter(ParameterSetName='Raw',             Mandatory=$true)]
        [switch]$Raw,

        [Parameter(ParameterSetName='Canceled',        Mandatory=$true)]
        [switch]$Canceled,

        [Parameter(ParameterSetName='Executing',       Mandatory=$true)]
        [switch]$Executing,

        [Parameter(ParameterSetName='Failed',          Mandatory=$true)]
        [switch]$Failed,

        [Parameter(ParameterSetName='Queued',          Mandatory=$true)]
        [switch]$Queued,

        [Parameter(ParameterSetName='Success',         Mandatory=$true)]
        [switch]$Success,

        [Parameter(ParameterSetName='Canceled')]
        [Parameter(ParameterSetName='Failed')]
        [Parameter(ParameterSetName='Queued')]
        [Parameter(ParameterSetName='Executing')]
        [Parameter(ParameterSetName='Success')]
        [Alias('Take')]
        [int]$First = 50
    )
    process {
        foreach ($state in @('Canceled','Executing', 'Failed','Queued', 'Success')) {
            if ($PSBoundParameters.ContainsKey($state)) {
                Invoke-OctopusMethod -PSType OctopusTask -EndPoint "tasks?States=$state&take=$First" -ExpandItems
                return
            }

        }
        #Invoke-OctopusMethod -PSType OctopusTask -EndPoint "tasks?running=true&take=$First" -ExpandItems


        if     ($Task.TaskId) {$Task = $Task.TaskId}
        elseif ($Task.Id)     {$Task = $Task.Id}
        if     ($Task -notmatch '^\w+tasks-\d+$') {
                Write-Warning "$Task doesn't look like a valid task ID it should be in the from tasks-12345 "
                return
        }
        $item = Invoke-OctopusMethod -PSType OctopusTask -EndPoint "tasks/$Task"

        if     ($Artifacts) {$item.Artifacts()}
        elseif ($Details)   {$item.Details()}
        elseif ($Raw)       {$item.Raw() }
        else                {$item}
    }
}

function Get-OctopusEvent                   {
<#
.example
Get-OctopusEvent projects-61 -OldestFirst | select msg | ogv
#>
    [cmdletbinding(DefaultParameterSetName='None')]
    param   (
        [Parameter(ParameterSetName='Event',   Mandatory=$true, ValueFromPipeline=$true, Position=0)]
        $ID,
        [Parameter(ParameterSetName='From',    Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [dateTime]$From,
        [Parameter(ParameterSetName='Days',    Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [int]$Days,
        [Parameter(ParameterSetName='Hours',   Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [int]$Hours,
        [Parameter(ParameterSetName='Today',   Mandatory=$true)]
        [switch]$Today,
        [Alias('Take')]
        [int]$First,
        [switch]$OldestFirst
    )
    if     ($ID.ID)    {$ID = $ID.ID}
    if     ($id -and    $ID -notmatch '-\d+$') {
                Write-Warning "'$ID' doesn't look like a valid ID"
                return
    }
    elseif ($ID -match '^Events-\d+$')     {
            Invoke-OctopusMethod -PSType OctopusEvent -EndPoint "events/$ID"
            return
    }

    $endpoint ='events'
    if     ($Days)   {$From      = [datetime]::Now.AddDays(-$Days)}
    elseif ($Hours)  {$From      = [datetime]::Now.AddHours(-$Hours)}elseif ($Today)       {$From      = [datetime]::Today}
    elseif ($ID)     {$endpoint += "?regardingAny=$ID"}
    if     ($From)   {$endpoint += '?from={0:yyyy/MM/dd HH:mm}' -f $From }

    $e = Invoke-OctopusMethod -PSType OctopusEvent  -EndPoint $endpoint -ExpandItems -First $First
    if ($OldestFirst) {$e | Sort-Object -Property Occurred} else {$e}
}

function Add-OctopusArtifact                {
    [cmdletbinding(SupportsShouldProcess=$true)]
    param   (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline)]
        [Alias('Id')]
        $Task,
        [Parameter(Mandatory=$true,Position=1)]
        $Path,
        [Parameter(Position=2)]
        $Name,
        [Alias('PT')]
        [switch]$PassThru,
        [switch]$Force
    )
    if ($Task.id) {$Task = $Task.ID}
    if (Test-Path $Path -PathType Leaf  ) {
        $Path    = Resolve-Path $Path
    }
    else {throw "$Path not found."}
    if (-not $Name) {
        $Name    = Split-Path -Leaf $Path
    }
    $artifact    = @{
        Filename         = $Name
        Source           = $null
        ServerTaskId     = $Task
        LogCorrelationId = $null
    }
    if ($env:OctopusSpaceID) {
        $artifact['SpaceId'] = $env:OctopusSpaceID
    }
    if ($Force -or $pscmdlet.ShouldProcess($Task,"Add file $Name as artifact of task")) {
        $newartifact = Invoke-OctopusMethod -Method Post -EndPoint artifacts -Item $artifact
        Invoke-OctopusMethod -EndPoint $newartifact.Links.Content  -Method Put -RawParams @{InFile=$Path}
        if ($PassThru) {$newartifact}
    }
}

function Get-OctopusArtifact                {
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',           Mandatory=$false, Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Download',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [alias('Artifact')]
        $ID,

        [Parameter(ParameterSetName='Download',          Mandatory=$True,  Position=1, ValueFromPipelineByPropertyName=$true)]
        $Destination,

        [Parameter(ParameterSetName='Download',          Mandatory=$false)]
        [Alias('PT')]
        [switch]$PassThru
    )
    process {
        if     ($ID.id -and $ID.fileName -and $ID.links) {$artifact = $ID}
        elseif ($ID -is [string] -and $ID -match '^Artifacts-\d+$' ) {
                $artifact   = Invoke-OctopusMethod -EndPoint "artifacts/$ID" -PSType 'OctopusArtifact'
        }
        else   {throw "$id does not appear to be a valid artifact."}
        if     (-not $Destination) {return $artifact}
        else   { #if we have destination directory,  download the artifact
            $file = $artifact.Download($Destination)
            if ($PassThru) {$file}
        }
    }
}
