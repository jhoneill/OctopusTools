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

        $Type = "info|error|fatal",

        $Exclude = "Artifacts for collection|Keeping this deployment|Did not find any deployments|Extracting package|Delta|Found Matching version|Using Package"
    )
    if     ($Task.TaskId) {$Task = $Task.TaskId}
    elseif ($Task.Id)     {$Task = $Task.Id}
    if     ($Task -notmatch '^\w+tasks-\d+$') {
            Write-Warning "$Task doesn't look like a valid task ID it should be in the from tasks-12345 "
            return
    }
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