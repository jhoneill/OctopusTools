function Watch-OctopusTask                  {
    <#
      .SYNOPSIS
        Outputs a tail of the log for a the specified task

      .PARAMETER Task
        A task ID or Task object, or an object with a Task ID, like a a deployment

      .PARAMETER Type
        The type of log message to include in the output (see Format-OctopusLog for more details)

        .EXAMPLE
        An example
    #>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(Position=0,ValueFromPipeline=$true, Mandatory=$true)]
        [Alias('ID')]
        $Task,

        $Type = "info|error|fatal"
    )

        if     ($Task.TaskId) {$Task = $Task.TaskId}
        elseif ($Task.Id)     {$Task = $Task.Id}
        if     ($Task -notmatch '^\w+tasks-\d+$') {
                Write-Warning "$Task doesn't look like a valid task ID it should be in the from tasks-12345 "
                return
        }
       # $tempPath = [System.IO.Path]::GetTempFileName()
       # $psdPath  = Resolve-Path "$PSScriptRoot\..\OctopusTools.psd1"

       # $null = Start-ThreadJob -ScriptBlock {
       #        $null = Import-Module $using:psdpath -Force
                $offset = 0
                do {
                    $t      = Get-OctopusTask  $task # $using:Task
                    $raw    = $t.raw()
                    $raw.Substring($offset) | Format-Octopuslog -Type $using:type # | Format-Table -HideTableHeaders | Out-string
                    #Add-Content -Path $using:temppath -Value ($text.trim() )
                    $offset = $raw.Length
                }  while ($t.State -eq 'Executing' -and (-not (Start-Sleep -Seconds 5)))
        #}
        #while (-not (Test-Path $tempPath)) {Start-sleep -Seconds 1} # Give the thread job a chance to start
        #Get-Content -Wait $temppath
}