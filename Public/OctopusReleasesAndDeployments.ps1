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
        if      ($Release -is [string] -and $Release -match '^Projects-\d+$') {
                 $Release = Get-OctopusProject -Project $Release
        }
        elseif  ($Release.Releases)  {$Release = $Release.Releases()}
        foreach    ($r in $Release) {
            if     ($r.pstypenames -contains 'OctopusRelease') { #Already a deployment
                    $item = $r
            }
            else {
                if     ($r.ReleaseId) {$r = $r.ReleaseId}
                elseif ($r.Id)        {$r = $r.Id}
                if     ($r -notmatch '^Releases-\d+$') {
                        Write-Warning "'$r' doesn't look like a valid release: ID it should be in the from releases-12345 "
                        if ($r -is [string] -and $PSBoundParameters.ContainsKey('Project')){
                            Write-Warning "Did you intend  Get-OctopusProject '$r' -AllReleases "
                        }
                        continue
                }
                $item = Invoke-OctopusMethod -PStype OctopusRelease -EndPoint "releases/$r"
            }
            if     (-not $item)   {Continue}
            elseif ($Artifacts)   {$item.Artifacts()}
            elseif ($Deployments) {$item.Deployments()}
            elseif ($LifeCycle)   {$item.LifeCycle()}
            elseif ($Phases)      {$item.Progression()}
            elseif ($Project)     {$item.Project()}
            else                  {$item}
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
        if      ($Deployment -is [string] -and $Deployment -match '^releases-\d+$') {
                 $Deployment = Get-OctopusRelease -Release $Deployment
        }
        #if we got a relase or just expanded a release ID to a release use it's Deployments method
        if       ($Deployment.Deployments)  {$Deployment = $Deployment.Deployments()}
        foreach ($d in $Deployment) {
            if     ($d.pstypenames -contains 'OctopusDeployment') { #Already a deployment
                    $item = $d
            }
            else   {
                if     ($d.DeploymentId) {$d = $d.DeploymentId}
                elseif ($d.Id)           {$d = $d.Id}

                if     ($d -match '^Deployments-\d+$') {  #we got a deployment ID, get its deployment.
                        $item = Invoke-OctopusMethod -PSType OctopusDeployment -EndPoint "deployments/$d"}
                elseif ($d -match   '^Projects-\d+$')    { #there's an API call to get a projects deployments direcly.
                        $item = Invoke-OctopusMethod -PSType OctopusDeployment -EndPoint "deployments?projects=$d" -ExpandItems -First 100
                }
                else   {
                        Write-Warning "'$d' doesn't look like a valid Deployment ID it should be in the from Deployments-12345 "
                        continue
                }
            }
            if     (-not $item) {continue}
            elseif ($Artifacts) {$item.Artifacts()}
            elseif ($Process)   {$item.DeploymentProcess()}
            elseif ($Project)   {$item.Project()}
            elseif ($Release)   {$item.Release() }
            elseif ($Task)      {$item.Task() }
            else                {$item}
        }
    }
}

function Get-OctopusTask                    {
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(Position=0,ValueFromPipeline=$true )]
        [Alias('ID')]
        $Task,

        [Parameter(ParameterSetName='Artifacts',       Mandatory=$true)]
        [switch]$Artifacts,

        [Parameter(ParameterSetName='Details',         Mandatory=$true)]
        [switch]$Details,

        [Parameter(ParameterSetName='Raw',             Mandatory=$true)]
        [switch]$Raw,

        # Queued, , Failed, Canceled, TimedOut, Success, Cancelling
        [switch]$Executing,
        [switch]$Failed,
        [switch]$Success,
        [switch]$Queued,
        [switch]$Canceled,

        [Alias('Take')]
        [int]$First = 50
    )
    process {
        if (-not $Task) {
            foreach ($state in @('Canceled','Executing', 'Failed','Queued', 'Success')) {
                if ($PSBoundParameters.ContainsKey($state)) {
                    Invoke-OctopusMethod -PSType OctopusTask -EndPoint "tasks?States=$state&take=$First" -ExpandItems
                    $gotAllForState = $true
                }
            }
        }
        if   ($gotAllForState) {return }
        else {$stateRegex =  @('Canceled','Executing', 'Failed','Queued', 'Success').Where({$PSBoundParameters.ContainsKey($_)}) -join '|'}
        if   (-not $stateRegex) {$stateRegex = '.'}

        if      (  ($Task -is [string] -and $Task -match '^releases-\d+$|^Deployments-\d+$|^Projects-\d+$') -or
                   ($Task.id -and $Task.id -match '^releases-\d+$|^Projects-\d+$' -and -not $Task.TaskId)) {
                    $Task =  Get-OctopusDeployment -Deployment $Task
        }
        foreach ($t in $Task) {
            if  ($t.pstypenames -contains 'OctopusTask' ) {
                $item = $t
            }
            else {
                if     ($t.TaskId) {$t = $t.TaskId}
                elseif ($t.Id)     {$t = $t.Id}
                if     ($t -notmatch '^\w+tasks-\d+$') {
                        Write-Warning "$t doesn't look like a valid task ID it should be in the from tasks-12345 "
                        continue
                }
                $item = Invoke-OctopusMethod -PSType OctopusTask -EndPoint "tasks/$t"
            }
            if     (-not $item -or $item.state -notmatch $stateRegex) {Continue}
            elseif ($Artifacts) {$item.Artifacts()}
            elseif ($Details)   {$item.Details()}
            elseif ($Raw)       {$item.Raw() }
            else                {$item}
        }
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
