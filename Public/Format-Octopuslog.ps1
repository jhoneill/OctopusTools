function Format-OctopusLog                  {
<#
    .SYNOPSIS
        Returns a filtered view of a Raw Octopus log as time and message

    .DESCRIPTION
        Each line in the raw log is time stamped and flagged as information,verbose,Warning,error, or fatal, and the message is indented to convey a hierachy.
        This command splits the lines, works out the hierarchy level from the indent, filters by type (using regular expressions), and level and outputs the mmessage and timestamp.

    .PARAMETER InputObject
        The log -usually piped in

    .PARAMETER MaxLevel
        The highest level of indent allowed

    .PARAMETER Type
        The event type such as error, this is a regular expression so you can use ' |info' for "Matching space or 'info", or 'error|fatal' for "error or fatal"

    .PARAMETER Property
        The data is split into Time, Level, Type, and Message. For on-screen viewing it is simply output as a Time and message, but you specify *, or anything that is valid in a select-object command

    .EXAMPLE
        C:> Format-Octopuslog .\logfile.txt -Type "fatal"
        Outputs "Fatal" level messages from logfile.txt

    .EXAMPLE
        $p = Get-OctopusProject projects-123 ;
        $p.releases() | Select-Object -First 5 | ForEach-Object {
            foreach ($d in $_.deployments() ) {
                $t =$d.task()
                Format-Octopuslog -type "error" -InputObject $t.raw() -Property @{n='datetime';e={$t.StartTime.Date.Add([timespan]::Parse($_.Time)) }},message
            }
        }
        The first line gets a project, the second gets its releases and selects only the first 5.
        For each deployment in each of the selected releases the task is fetched and
        the log is formatted with a custom string which joins the time in the log to the date from the task.

     .EXAMPLE
        C:> (gop projects-881).Releases()[0..4].Deployments().task().raw() | fol  -MaxLevel 3 | Out-GridView
        A terser form of the previous command with the timestamp gymnastics.
        The first command uses the alias gop for *G*et *O*ctopus *P*roject. Calls the Project's Releases() method,
        selects 5 releases, gets their Deployments, their Tasks, and their raw file,  Filters the logs
        to higher-level messages (using the alias fol for *F*ormat *O*ctopus *L*og) and displays them in a grid view.
#>

    [alias('fol')]
    param (
        [Parameter(Position=0,ParameterSetName='File')]
        $Path,
        [Parameter(ValueFromPipeline=$true,ParameterSetName='String')]
        [string]$InputObject,

        [int]$MaxLevel = 100,

        [String]$Type,

        $Property = @('Time', 'Message')
    )
    process {
        if ($Path) {$InputObject = Get-Content $Path -Raw}
        $InputObject -split "[\r\n]+" |  ForEach-Object {
            #We either have TIME  TYPE "|"" {some indent indicating nesting} MESSAGE ...
            if ( $_ -match "(^\d\d:\d\d:\d\d|\s{8})\s+(\w+|\s)\s+\| (\s*)(\S.*$)") {
                [pscustomobject]@{"Time"=$matches[1];'Level'=($matches[3].length /2); 'Type'=$matches[2];  ; 'Message'=$matches[3]+$matches[4]}
            }
            #or a line with just "|" and white space, or message we can't parse.
            elseif ($_ -notmatch "^[\|\s]*$") {
                [pscustomobject]@{"Time"=$Null;      'Level'=0;                       'Type'=$null;         ;'Message'=$_}
            }
        } | #filter to level and type requested and just give time and message.
            Where-Object  {$_.Level -le $MaxLevel -and ((-not $type) -or $_.type -match $Type) } | Select-Object $property
    }
}
