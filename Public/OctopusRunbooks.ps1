function New-OctopusRunbookSnapShot         {
    [cmdletbinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
        $Runbook,

        [Parameter(Position=1)]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $Project,

        [switch]$NoPublish,

        [switch]$Force
    )
    if     ($Runbook -is [string] -and $runbook -match "^Runbooks-\d+$" ) {
            $Runbook = Invoke-OctopusMethod -PSType OctopusRunbook -EndPoint "/runbooks/$Runbook"}
    elseif ($Runbook -is [string]  -and  $Project) {
            $Runbook= Get-OctopusProject $Project -Runbooks | Where-Object name -like $Runbook
    }
    if (-not ($Runbook.id -and $Runbook.Links.RunbookSnapshotTemplate -and $Runbook.ProjectId)) {
            throw "can't get runbook from the information provided"
    }

    $template     = Invoke-OctopusMethod $Runbook.Links.RunbookSnapshotTemplate
    $body         = @{
        ProjectId            = $Runbook.ProjectId
        RunbookId            = $Runbook.Id
        Name                 = $template.NextNameIncrement
        Notes                = $null
        SelectedPackages     = @()
    }
    # add latest built-in feed packages
    foreach($package in $template.Packages.Where({ $_.FeedId -eq "feeds-builtin"})) {
        $body.SelectedPackages  += @{
            ActionName           = $package.ActionName
            PackageReferenceName = $package.PackageReferenceName
            Version              =  Invoke-OctopusMethod "feeds/feeds-builtin/packages/versions?packageId=$($package.PackageId)&take=1" -ExpandItems | Select-Object -First 1 -ExpandProperty version
        }
    }
    if ($Force -or $PSCmdlet.ShouldProcess($Runbook.Name,'Create new runbook snapshot')) {
        $newSnapShot =  (Invoke-OctopusMethod   "/runbookSnapshots?publish=$(-Not [bool]$NoPublish)" -Item $body -Method Post)
        if (-not $NoPublish) {
            $Runbook.PublishedRunbookSnapshotId = $newSnapShot.id
            $null = Invoke-OctopusMethod -PSType OctopusRunbookSnapshot -Method Put -EndPoint $Runbook.links.Self -Item $Runbook
        }
        return $newSnapShot
    }
}

function Get-OctopusRunbookSnapShot         {
<#
.example
Get-OctopusProject he* -Runbooks | Get-OctopusRunbookSnapShot -Runs | foreach {Get-Octopustask $_.taskid}
.example
Get-OctopusProject he* -Runbooks | Get-OctopusRunbookSnapShot -Runs | ogv  -PassThru | foreach {$_.delete()}
#>
   [cmdletbinding(DefaultParameterSetName="ByID")]
   param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0,ParameterSetName="ByRunbook")]
        $Runbook,

        [Parameter(Position=1,ParameterSetName="ByRunbook")]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $Project,

        [Parameter(ParameterSetName="ByID")]
        $ID,

        [switch]$Runs
    )
    if ($id) {
              $item = Invoke-OctopusMethod -PSType OctopusRunbookSnapshot -EndPoint "runbookSnapshots/$ID"
    }
    else {
        if       ($Runbook -is [string]  -and  $Runbook -match "^Runbooks-\d+$" ) {
                  $Runbook = Invoke-OctopusMethod -PSType OctopusRunbook -EndPoint "/runbooks/$Runbook"}
        elseif   ($Runbook -is [string]  -and  $Project) {
                  $Runbook= Get-OctopusProject $Project -Runbooks | Where-Object name -like $Runbook
        }
        if (-not ($Runbook.id -and $Runbook.Links.RunbookSnapshotTemplate -and $Runbook.ProjectId)) {
                  throw "can't get runbook from the information provided"
        }

        $item = Invoke-OctopusMethod -PSType OctopusRunbookSnapshot -EndPoint ($runbook.Links.RunbookSnapshots -replace "\{.*$","") -ExpandItems
    }
    if ($Runs) {
        foreach ($i in $item)  {
            Invoke-OctopusMethod -PSType OctopusRunbookRun -EndPoint ($i.Links.RunbookRuns -replace "\{.*$","") -ExpandItems
        }
    }
    else {$item}
}

function Start-OctopusRunbook               {
    [cmdletbinding(SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
        $Runbook,

        [Parameter(Position=1)]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $Project,

        #$Tennant ,
        [Parameter(Mandatory=$true)]
        [ArgumentCompleter([OctopusEnvironmentNamesCompleter])]
        [string[]]$Environment ,

        $SnapshotID ,
        [switch]$Force
    )
    if       ($Runbook -is [string]  -and  $Runbook -match "^Runbooks-\d+$" ) {
              $Runbook = Invoke-OctopusMethod -PSType OctopusRunbook -EndPoint "/runbooks/$Runbook"}
    elseif   ($Runbook -is [string]  -and  $Project) {
              $Runbook= Get-OctopusProject $Project -Runbooks | Where-Object name -like $Runbook
    }
    if (-not ($Runbook.id -and $Runbook.Links.RunbookSnapshotTemplate -and $Runbook.ProjectId)) {
            throw "can't get runbook from the information provided"
    }

    if     (-not $SnapshotID -and $Runbook.PublishedRunbookSnapshotId) {
            throw "this runbook has not been published, either provide a snapshot ID or publish the runbook."
    }
    elseif (-not $SnapshotID) {$SnapshotID = $Runbook.PublishedRunbookSnapshotId}

    $tenantId = $null
    <# Optionally get tenant
    if (![string]::IsNullOrEmpty($tenantName)) {
        $tenant = (Invoke-RestMethod -Method Get -Uri "$OctopusURL/api/$($space.Id)/tenants/all" -Headers $header) | Where-Object {$_.Name -eq $tenantName} | Select-Object -First 1
        $tenantId = $tenant.Id
    }
    #>

    # Get environments
    $Environment | Get-OctopusEnvironment  | ForEach-Object {
        if ($Force -or $PSCmdlet.ShouldProcess($_.name,"Execute runbook $($Runbook.Name)")) {
            Invoke-OctopusMethod -PSType OctopusRunbookRun -Method Post -EndPoint runbookRuns -Item  @{
                EnvironmentId      = $_.id
                TenantId           = $tenantId
                RunbookId          = $Runbook.Id
                RunbookSnapshotId  = $SnapshotID
                SkipActions        = @()
                SpecificMachineIds = @()
                ExcludedMachineIds = @()
            }
        }
    }
}
