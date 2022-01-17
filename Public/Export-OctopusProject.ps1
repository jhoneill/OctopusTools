
function Export-OctopusProject              {
    <#
      .SYNOPSIS
        Creates a Zip file holding one or more projects, and optionally downloads it.

      .DESCRIPTION
        On versions Octopus Deploy which support it (version 2021.1 and later),
        submits a job to the server to extract information about projects and Zip it for download
        The command can either return the job ID or wait and download the file.
        The Zip file password doesn't seem to be working on the server side currently.

      .PARAMETER Project
        One or more Project objects, Project Names, or Project IDs to export

      .PARAMETER ZipFilePwd
        Optional password ot use on the zip file

      .PARAMETER Destination
        Directory or file name to copy the zip file(s) to

      .PARAMETER TimeOut
        Maximum time to allow the job to complete

      .PARAMETER ProgressPreference
        Allows the Progress bar act differently in the function, specifying silentlyContinue will suppress it.
    #>
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $Project,
        $ZipFilePwd = "DontTellany1!",
        $ZipDestination,
        $TimeOut=300,
        [ActionPreference]$ProgressPreference = $PSCmdlet.GetVariableValue('ProgressPreference')
    )
    begin {
        if ((Invoke-OctopusMethod api).version -lt [version]::new(2021,1)) {
            throw "This requires at least version 2021.1 of Octopus Deploy"
        }
        if ($PSBoundParameters['ZipFilePwd'] -and -not $ZipDestination) {$ZipDestination = $pwd}
        elseif ($ZipDestination -and -not (Test-Path -PathType Container $ZipDestination)) {
            throw 'FileDestination should be a directory'
        }
       $Body = @{
            IncludedProjectIds = @();
            Password           = @{HasValue = $True; NewValue = $ZipFilePwd; }
        }
    }
    process {
        foreach     ($p in $project) {
            if      ($p.id ) {$body.IncludedProjectIds += $p.Id}
            elseif  ($p -is [string] -and $p -match "^projects-\d+$") {$Body.IncludedProjectIds += $p}
            else    {$Body.IncludedProjectIds += (Get-OctopusProject $p ).id }
        }
    }
    end {
        $Body.IncludedProjectIds = @($Body.IncludedProjectIds | Where-Object {$_ -match "^projects-\d+$"} | Sort-Object -Unique)
        if (-not $Body.IncludedProjectIds) {
            Write-Warning "No Projects matched"
            return
        }
        $startTime        = [datetime]::now
        $exportServerTask = Invoke-OctopusMethod -EndPoint "/projects/import-export/export" -Method Post -Item $body

        if     (-not $ZipDestination ) {
                Get-OctopusTask $exportServerTask.TaskId
                return
        }
        #else ...
        do     {
            $t = Get-OctopusTask $exportServerTask.TaskId
            if ($t.State  -eq "Success") {
                $t.Artifacts() | Where-Object filename -like "*.zip" | ForEach-Object {$_.download($ZipDestination)}
            }
            elseif (-not $t.IsCompleted) {
                Write-Progress -Activity "Waiting for server task to complete" -SecondsRemaining ($startTime.AddSeconds($TimeOut).Subtract([datetime]::now).Totalseconds) -Status $t.State
            }
        }
        While  ((-not $t.IsCompleted) -and [datetime]::now.Subtract($startTime).totalseconds -lt $TimeOut -and
                (-not (start-sleep -Seconds 5))   #Sneaky trick. This waits for 5 seconds and returs true. So we only wait if we're going to go round again.
                )
        if     ( -not $t.IsCompleted) {
                Write-warning "Task Timed out. Cancelling"
                Write-Progress -Activity "Waiting for server task to complete" -SecondsRemaining 0 -Status $t.State
                $null = Invoke-OctopusMethod  -EndPoint $t.Links.Cancel -Method post
        }
        elseif ($t.State -ne "Success") {
                Write-warning "Task completed with Status of $($t.State)"
        }
        Write-Progress -Activity "Waiting for server task to complete" -Completed
    }
}
