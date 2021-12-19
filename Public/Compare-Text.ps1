if ($Host.UI.SupportsVirtualTerminal) {  #Relies on ANSI sequences

function Compare-Text {
        <#
        .SYNOPSIS
            A wrapper for the built in Compare-Object function to do nice text comparison

        .PARAMETER ReferenceText
            Parameter Specifies an array of strings used as a reference for comparison.

        .PARAMETER DifferenceText
            Specifies the strings that are compared to the reference strings.

        .PARAMETER SyncWindow
            Specifies the number of adjacent objects that `Compare-Object` will be asked to inspect while looking for a match
            (It examines adjacent objects when it doesn't find the object in the same position in a collection.)
            The default value is `[Int32]::MaxValue`, so the entire collection will examined.

        .PARAMETER Culture
            Specifies the culture to use for comparisons.

        .PARAMETER CaseSensitive
            Indicates that comparisons should be case-sensitive.

        .EXAMPLE
            ps > Compare-Text (gc .\ConfigureDNS1.json) (gc .\ConfigureDNS2.json)

            Compares the contents of two files

        .EXAMPLE
            ps > $file1 = Get-content .\ConfigureDNS1.json;
            ps > cat .\ConfigureDNS2.json |  Compare-Text $file1

            This does the same as the previous example, but this time the reference file
            is pre-loaded and the difference file is piped into the command.

        .EXAMPLE
            ps > $before = $Process.Steps.Actions | Out-String -stream
            [after making changes]
            ps > $Process.steps.actions | out-string -Stream | Compare-Text $before

            The first command stores what a series of 'actions' look like, when printed as text
            and the second compares what output looks like after a series of changes
    #>
    param(
            [Parameter(Mandatory=$true, Position=0)]
            [AllowEmptyCollection()]
            [object[]]$ReferenceText,

            [Parameter(Mandatory=$true, Position=1, ValueFromPipeline=$true)]
            [AllowEmptyCollection()]
            [Object[]]$DifferenceText,

            [string]$IgnoreChanges,

            [ValidateRange(0, 2147483647)]
            [int32]$SyncWindow,

            [string]$Culture,

            [switch]$CaseSensitive,

            [ConsoleColor]$AddedColor     = 'Green',

            [ConsoleColor]$RemovedColor   = 'Red',

            [ConsoleColor]$MovedColor     = 'DarkCyan',

            [ConsoleColor]$UnchangedColor = 'DarkGray',

            [switch]$NoStrikeThrough
        )
        #If difference text is piped in build it up in $differenceObject
        begin   {
            $styleMap = @{
                'Black'       = $PSStyle.Foreground.Black
                'DarkBlue'    = $PSStyle.Foreground.Blue
                'DarkGreen'   = $PSStyle.Foreground.Green
                'DarkCyan'    = $PSStyle.Foreground.Cyan
                'DarkRed'     = $PSStyle.Foreground.Red
                'DarkMagenta' = $PSStyle.Foreground.Magenta
                'DarkYellow'  = $PSStyle.Foreground.Yellow
                'Gray'        = $PSStyle.Foreground.White
                'DarkGray'    = $PSStyle.Foreground.BrightBlack
                'Blue'        = $PSStyle.Foreground.BrightBlue
                'Green'       = $PSStyle.Foreground.BrightGreen
                'Cyan'        = $PSStyle.Foreground.BrightCyan
                'Red'         = $PSStyle.Foreground.BrightRed
                'Magenta'     = $PSStyle.Foreground.BrightMagenta
                'Yellow'      = $PSStyle.Foreground.BrightYellow
                'White'       = $PSStyle.Foreground.BrightWhite
                }

            $ansiMap  = @{
                'Black'       = "$([char]27)[30m"
                'DarkBlue'    = "$([char]27)[34m"
                'DarkGreen'   = "$([char]27)[32m"
                'DarkCyan'    = "$([char]27)[36m"
                'DarkRed'     = "$([char]27)[31m"
                'DarkMagenta' = "$([char]27)[35m"
                'DarkYellow'  = "$([char]27)[33m"
                'Gray'        = "$([char]27)[37m"
                'DarkGray'    = "$([char]27)[90m"
                'Blue'        = "$([char]27)[94m"
                'Green'       = "$([char]27)[92m"
                'Cyan'        = "$([char]27)[96m"
                'Red'         = "$([char]27)[91m"
                'Magenta'     = "$([char]27)[95m"
                'Yellow'      = "$([char]27)[93m"
                'White'       = "$([char]27)[97m"
            }


            if ($PSStyle) {
                $addedSeq     = $styleMap[$AddedColor.ToString()]
                $movedSeq     = $styleMap[$MovedColor.ToString()]
                $removedSeq   = $styleMap[$RemovedColor.ToString()]
                $unchangedSeq = $styleMap[$UnchangedColor.ToString()]
                $resetSeq     = $PSStyle.Reset
                $stSeq        = $PSStyle.Strikethrough
            }
            else {
                $addedSeq     = $ansiMap[$AddedColor.ToString()]
                $movedSeq     = $ansiMap[$MovedColor.ToString()]
                $removedSeq   = $ansiMap[$RemovedColor.ToString()]
                $unchangedSeq = $ansiMap[$UnchangedColor.ToString()]
                $resetSeq     = "$([char]27)[0m"
                $stSeq        = "$([char]27)[9m"
            }
            if ($NoStrikeThrough) {$stSeq       = ""}
            if ($IgnoreChanges)   {$ignoreRegEx = [regex]::new($IgnoreChanges ,'Compiled') }

            $DifferenceObject = @()
        }
        #If difference text is piped in build it up in $differenceObject
        process {$DifferenceObject += $DifferenceText}
        end     {
            if  ($DifferenceObject.Count -eq 1 -and (Test-Path $DifferenceObject[0]) ) {
                 $DifferenceObject       =   Get-Content -Path $DifferenceObject[0]
            }
            if  ($ReferenceText.Count    -eq 1 -and (Test-Path $ReferenceText[0]) ) {
                 $ReferenceText          =   Get-Content -Path $ReferenceText[0]
            }
            # Numbered every line. Get-Content does that for us, see https://www.leeholmes.com/using-powershell-to-compare-diff-files/
            # recounts for files start at 1 so we will add numbers starting at 1 if they aren't there already.

            if (-not    $ReferenceText[0].readcount ) {
                $i = 1
                $ReferenceText    = $ReferenceText    | ForEach-Object {Add-Member -InputObject $_ -NotePropertyName 'ReadCount' -NotePropertyValue ($i ++) -force -PassThru}
            }
        `   if (-not $DifferenceObject[0].readcount ) {
                $i = 1
                $DifferenceObject = $DifferenceObject | Foreach-object {Add-Member -InputObject $_ -NotePropertyName 'ReadCount' -NotePropertyValue ($i ++) -force -PassThru}
            }

            $params       = @{IncludeEqual=$true; ReferenceObject=$ReferenceText; DifferenceObject= $DifferenceObject ; CaseSensitive =($CaseSensitive -as [boolean]) }
            if ($Culture)    {$params['Culture']    = $Culture}
            if ($SyncWindow) {$params['SyncWindow'] = $SyncWindow }
            $comparison   = Compare-Object @params
            <#The comparison has text & linenumber_in_REF if the text is on both sides or only
            in "REF",  & it has text & lineNumber_in_DIF if the text is  only only the DIF side.
            But text being on both sides does not mean matching line numbers! So...
            Step 1: Find the lines on each side which are unique to that side
            #>
            $refonlyLines = $comparison.where({$_.sideindicator -eq '<='}).inputobject.readcount
            $difonlyLines = $comparison.where({$_.sideindicator -eq '=>'}).inputobject.readcount
            $refcount     = $difCount  = 1
            <#Step 2: Read down both sides. If one side has hit a line is unique to it, colour-code for that side,
            and move to the next line on that side only. If the line is on both sides, colour-code for equal
            and move both sides to the next line. Don't forget file line numbers start at 1 but arrays at 0 !#>
            $refsSkipped = @{}
            $difsAhead   =@{}
            while  ($refCount -lt $ReferenceText.Count -or  $difcount -lt $DifferenceObject.Count) {
                if ($refcount -gt $ReferenceText.Count)    {$refcount  =  $ReferenceText.Count}
                $r = $ReferenceText[$refcount -1]
                $d = $DifferenceObject[$difcount -1]
                if     ($refcount -in $refonlyLines -and (-not $ignoreRegEx -or -not $ignoreRegEx.IsMatch($r))) {($r -replace '^(\s*)', "`$1$stSeq$removedSeq") + $resetSeq ; $refcount ++ ;            $nextref = $refcount }
                elseif ($refcount -in $refonlyLines )                                                           {$unchangedSeq + $r + $resetSeq ;                             $refcount ++ ;            $nextref = $refcount }
                elseif ($difcount -in $difonlyLines -and (-not $ignoreRegEx -or -not $ignoreRegEx.IsMatch($d))) {$addedSeq     + $d + $resetSeq ; $difcount ++ ;                                                               $difsAhead[$d] ++}
                elseif ($difcount -in $difonlyLines)                                                            {$unchangedSeq + $d + $resetSeq ; $difcount ++ ;                                                               $difsAhead[$d] ++}
                else    {
                    # if the reference line is one the diff side has already done, move ref forward to catch up
                    while      ($r -and $difsAhead[$r] -and $refcount -lt $ReferenceText.Count){                                                                              $refcount ++ ;                                   $difsAhead[$r] --
                                                    $r = $ReferenceText[$refcount -1]}
                    if         ($r -eq $d)                                                                      {$unchangedSeq + $d + $resetSeq ; $difcount ++ ;              $refcount ++ ;            $nextref = $refcount }
                    else {
                       # if     ($refcount -notin $refonlyLines)  {
                                                    if (-not $refsSkipped[$r]) {$refsSkipped[$r] = $refcount}                                                                 $refcount ++
                                                    $r = $ReferenceText[$refcount -1]
                            while ($r -and $difsAhead[$r] -and $refcount -lt $ReferenceText.Count){                                                                           $refcount ++  ;                                  $difsAhead[$r]  --
                                                    $r = $ReferenceText[$refcount -1]}
                        #}
                        if     ($r -eq $d)                                                                      {$unchangedSeq + $d + $resetSeq ; $difcount ++ ;              $refcount ++ ;            $nextref = $refcount }
                        elseif ($refsSkipped[$d] -eq $nextref -or $d -eq $ReferenceText[$nextref -1])           {$unchangedSeq + $d + $resetSeq ; $difcount ++ ;              $refcount = $nextref +1 ; $nextref = $refcount ; $refsSkipped[$d] = $null }
                        elseif ($refsSkipped[$d] -and (-not $ignoreRegEx -or -not $ignoreRegEx.IsMatch($d)))    {$movedSeq     + $d + $resetSeq ; $difcount ++ ;                                                               $refsSkipped[$d] = $null }
                        elseif ($refsSkipped[$d])                                                               {$unchangedSeq + $d + $resetSeq ; $difcount ++ ;                                                               $refsSkipped[$d] = $null }
                        elseif (-not $ignoreRegEx -or -not $ignoreRegEx.IsMatch($d))                            {$addedSeq     + $d + $resetSeq ; $difcount ++ ;                                                               $difsAhead[$d] ++        }
                        else                                                                                    {$unchangedSeq + $d + $resetSeq ; $difcount ++ ;                                                               $difsAhead[$d] ++        }
                    }
                }
            }
        }
    }
}