function Watch-OctopusTask                  {
    <#
      .SYNOPSIS
        Outputs a tail of the log for a the specified task

      .PARAMETER Task
        A task ID or Task object, or an object with a Task ID, like a a deployment

      .PARAMETER Type
        The type of log message to include in the output (see Format-OctopusLog for more details)

      .PARAMETER Toast
        Instead of printing the log, if you have the Burnt Toast module installed, watch can start a
        ThreadJob to monitor the status of the job the status of the task

      .PARAMETER NotifySound
        Adds a sound to the the toast notification if specified, -Toast  is assumed.

      .EXAMPLE
        ps >  Get-OctopusProject -Project 'Banna'  | Get-OctopusDeployment | select -First 1  | Watch-OctopusTask
        The first command in the pipeline gets a project  an  the next two isolate the most recent deployment for that project,
        even if it wasn't for the most recent Release. Watch-Octopus task then "tails" the log file to the screen until it is interupted.

      .EXAMPLE
        ps >  Get-OctopusProject -Project 'Banna' -LastRelease | Get-OctopusTask -queued -executing | Watch-OctopusTask -toast
        The first command in the pipeline gets the most recent release for the project, and the second finds all the
        tasks associated with that are running or waiting to run and requests toast messages when they complete.
    #>
    [cmdletBinding(DefaultParameterSetName='TailLog')]
    param        (
        [Parameter(Position=0,ValueFromPipeline=$true, Mandatory=$true)]
        [Alias('ID')]
        $Task,

        [Parameter(ParameterSetName="TailLog")]
        $Type = "info|error|fatal",

        [Parameter(ParameterSetName="TailLog")]
        $Exclude = "Artifacts for collection|Keeping this deployment|Did not find any deployments|Extracting package|Delta|Found Matching version|Using Package"
    )
    DynamicParam {
        $p = New-Object -TypeName RuntimeDefinedParameterDictionary
        if  (Get-Command -Name New-BurntToastNotification -ErrorAction SilentlyContinue) {
                $paramAttribute =      New-Object  -TypeName ParameterAttribute -Property @{ ParameterSetName = "Toast" ;Mandatory = $false}
                $attributes     =      New-Object  -TypeName System.Collections.ObjectModel.Collection[System.Attribute]
                $attributes.Add(      (Get-Command -Name     New-BurntToastNotification).Parameters['sound'].Attributes.where({$_.validvalues})[0])
                $attributes.add(       $paramAttribute)
                $p.Add("Toast",       (New-Object  -TypeName RuntimeDefinedParameter -ArgumentList "Toast",       Switch, $paramAttribute ) )
                $p.Add("NotifySound", (New-Object  -TypeName RuntimeDefinedParameter -ArgumentList "NotifySound", String, $attributes ) )
        }
        return  $p
    }
    Process      {
        if     ($Task.TaskId) {$Task = $Task.TaskId}
        elseif ($Task.Id)     {$Task = $Task.Id}
        if     ($Task -notmatch '^\w+tasks-\d+$') {
                Write-Warning "$Task doesn't look like a valid task ID it should be in the from tasks-12345 "
                return
        }
        if ($PSBoundParameters.Toast-or $PSBoundParameters.NotifySound) {
                $sound      = $PSBoundParameters["NotifySound"]
                $modulepath =  (Resolve-Path ( $PSScriptRoot + "\.."))
                Start-ThreadJob -Name "$task watcher" -ScriptBlock {
                    Import-Module (Join-path $using:modulepath "OctopusTools.psd1")

                    while (($t = Get-OctopusTask $using:Task) -and $t.state -eq 'Executing') {start-sleep -Seconds 5}
                    if ($t) {
                        $toastParams =  @{ Button                   = (New-BTButton -Content 'Open Task' -Arguments ($env:OctopusUrl+$t.Links.Web) )
                                           ExpirationTime           = ([datetime]::Now.AddHours(1))
                                           AppLogo                  =  (Join-path $using:modulepath "Octopus.png")}
                        if ($using:sound) {$toastParams['Sound']    = $using:sound }
                        New-BurntToastNotification @toastParams -Text $t.state, $t.Description
                    }
                } | Out-Null
        }
        else {
            $oldRaw  = @()
            do {
                $t   = Get-OctopusTask  $task  # need to keep checking it is still executing
                $raw = $t.raw() -split '[\r\n]+'

                $s   = (Compare-Object $oldRaw $raw| Where-Object sideindicator -eq '=>' | Select-Object -ExpandProperty Inputobject |
                            Format-Octopuslog -Type $Type|  Where-Object Message -NotMatch $Exclude |
                                Format-Table -HideTableHeaders | Out-string).Trim()
                if ($s) {$s}
                $oldraw = $raw
            }
            while ($t.State -eq 'Executing' -and (-not (Start-Sleep -Seconds 5)))
        }
    }
}
