function Get-OctopusProject                 {
    <#
    # ExampleFodder
    Get-OctopusProject 'Random Quotes' -Releases | ogv -PassThru | foreach {$_.delete()}
    Get-OctopusProject 'Random Quotes' -DeploymentProcess | % steps | % actions | % properties
    (OctopusProject here*).releases().where({$_.version -like '*20'}).Deployments()[0].task().raw()
    Invoke-OctopusMethod "projects/Projects-21/deploymentprocesses"                        | select -expand steps  |select -expand actions | select -expand properties
    #                    Invoke-OctopusMethod "projects/Projects-21/runbookProcesses/RunbookProcess-Runbooks-1" | select -expand steps  |select -expand actions | select -expand properties
    #                         "/projects/$($project.Id)/releases" -expand   ; Invoke-RestMethod -Method Delete -Uri "/releases/$($release.Id)" -Headers $header
    #>
    [cmdletBinding(DefaultParameterSetName='Default')]
    [Alias('gop')]
    param   (
        [Parameter(ParameterSetName='Default',           Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Channels',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='DeploymentProcess', Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='DeploymentSettings',Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='AllReleases',       Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='ReleaseVersion',    Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Runbooks',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Triggers',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Variables',         Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project,

        [Parameter(ParameterSetName='Channels', Mandatory=$true)]
        [switch]$Channels,

        [Parameter(ParameterSetName='DeploymentProcess', Mandatory=$true)]
        [switch]$DeploymentProcess,

        [Parameter(ParameterSetName='DeploymentSettings',Mandatory=$true)]
        [switch]$DeploymentSettings,

        [Parameter(ParameterSetName='AllReleases',       Mandatory=$true)]
        [Alias('AllReleases','R')]
        [switch]$Releases,

        [Parameter(ParameterSetName='ReleaseVersion',    Mandatory=$true)]
        [Alias('RV')]
        $ReleaseVersion,

        [Parameter(ParameterSetName='Runbooks',          Mandatory=$true)]
        [Alias('RB')]
        [switch]$RunBooks,

        [Parameter(ParameterSetName='Triggers',          Mandatory=$true)]
        [switch]$Triggers,

        [Parameter(ParameterSetName='Variables',         Mandatory=$true)]
        [switch]$Variables
    )
    process {
        $item = Get-Octopus -Kind Project -Key $Project -ExtraId ProjectID | Sort-Object -Property ProjectGroupName,Name
        #xxxx todo Some types still to add for these methods in the types.ps1mxl file
        if      (-not $item)                               {return}
        elseif  ($PSCmdlet.ParameterSetName -eq 'Default') {$item}
        elseif  ($Channels)           {$item.Channels()}
        elseif  ($DeploymentProcess)  {$item.DeploymentProcess()}
        elseif  ($DeploymentSettings) {$item.DeploymentSettings()}
        elseif  ($RunBooks)           {$item.Runbooks()}
        elseif  ($Triggers)           {$item.Triggers()}
        elseif  ($Variables)          {$item.Variables()}
        elseif  ($ReleaseVersion)     {$item.Releases()   | Where-Object {$_.version -like $ReleaseVersion} }
        else                          {$item.Releases() }
    }
}
