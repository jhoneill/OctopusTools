function Get-OctopusProject                 {
    <#
    # ExampleFodder
    Get-OctopusProject 'Random Quotes' -AllReleases | ogv -PassThru | foreach {$_.delete()}
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
        [Parameter(ParameterSetName='LastRelease',       Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='AllReleases',       Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='ReleaseVersion',    Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Runbooks',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Triggers',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Variables',         Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $Project,

        [Parameter(ParameterSetName='Channels', Mandatory=$true)]
        [switch]$Channels,

        [Parameter(ParameterSetName='DeploymentProcess', Mandatory=$true)]
        [switch]$DeploymentProcess,

        [Parameter(ParameterSetName='LastRelease',       Mandatory=$true)]
        [Alias('LR')]
        [switch]$LastRelease,

        [Parameter(ParameterSetName='AllReleases',       Mandatory=$true)]
        [Alias('Releases','AR')]
        [switch]$AllReleases,

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
        if      (-not $item)                               {return}
        elseif  ($PSCmdlet.ParameterSetName -eq 'Default') {$item }
        elseif  ($Channels)           {$item.Channels()           }
        elseif  ($DeploymentProcess)  {$item.DeploymentProcess()  }
        elseif  ($RunBooks)           {$item.Runbooks()           } #XXXX todo on runbook support
        elseif  ($Triggers)           {$item.Triggers()           } #and on OctopusDeploymentTrigger
        elseif  ($Variables)          {$item.Variables()          }
        elseif  ($LastRelease)        {$item.Releases(1)          }
        elseif  ($ReleaseVersion)     {$item.Releases()    | Where-Object {$_.version -like $ReleaseVersion} }
        else                          {$item.Releases()           }
    }
}
