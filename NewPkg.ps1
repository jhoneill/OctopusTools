param (
    [parameter(Position=0)]
    $path,
    $Project     = 'banana',
    $Environment = 'Test',
    $FeedName    = '*devops*',
    $apikey      = [pscredential]::new("x",(Import-Clixml  (join-path (split-path $profile ) AzDO_pat.xml) )).GetNetworkCredential().password,
    [switch]$Send,
    [switch]$Berserk
)

nuget.exe pack -Verbosity quiet -NoPackageAnalysis $Path
if (-not $?) {return}

#region show content of nupkg file
$pkg         = ([xml](Get-Content $Path)).Package.metadata
$outfile     = "$($pkg.id).$($pkg.Version).nupkg"
$destination = mkdir ([IO.Path]::GetTempFileName() -replace '.tmp$')
$destRegex   = [regex]($destination.FullName -replace "\\",".")
Write-Host   -ForegroundColor Yellow $outfile
Expand-Archive $outfile     -DestinationPath $destination
Get-ChildItem  $destination -Exclude package,_rels,'*Content_Types*.xml' |
    Get-childitem -Recurse -File | Format-Table @{n='Time';e= {$_.LastWriteTime.Add([System.TimeZoneInfo]::Local.GetUtcOffset([datetime]::now))}}, #times will come back from pkg as UTC but expanding makes them look local
                                                    length, @{n='File';e={$destRegex.Replace($_.fullname,'')}}
Remove-Item -Recurse -Force $destination
#endregion

if ($Send  -or $Berserk) {
    #Check if we have updated the version
    $feed    = Get-OctopusFeed $feedName
    $octoPkg = Get-OctopusPackage -Feed $feed -Package $pkg.id
    if ($octoPkg.Version -eq $pkg.Version) {
        Write-warning "Feed looks to have the same version as you're building, nuspec may need an update. "
    }

    $apikey  | clip  # When you can't have the nuget cred provider you'lll get prompted
    $source  = $feed.feeduri -replace '/nuget.*$' , '/nuget/v2'
    nuget.exe push -apikey $apikey -source $source $Outfile
    $octoPkg = Get-OctopusPackage  -Feed $feed -Package $pkg.id
    Write-Host -ForegroundColor Green "$($pkg.id) version $($pkg.version)"
    "" | clip # don't leave the API Key in the clipboard

    if ($octoPkg.Version -ne $pkg.Version)  {
        Write-warning "Seeing version $($octoPkg.Version), expected $($pkg.Version)"
    }
    elseif ($Berserk)  {
        Remove-Item $outfile
        $deployment = Get-OctopusProject $Project | Add-OctopusRelease -Confirm | Add-OctopusDeployment -Environment $Environment
        if ($deployment) {
            $task = Get-OctopusTask $deployment.taskid
            while ($task.state -eq 'Executing') {
                Write-Progress -Activity "Executing"
                Start-Sleep     -Seconds 5
                $task = Get-OctopusTask $deployment.taskID
            }
            Write-Host -ForegroundColor cyan  $task.State
            (Get-OctopusTask $deployment.taskID -raw) -split "[\r\n]+" |  ForEach-Object {
                if ( $_ -match "(^\d\d:\d\d:\d\d)\s+(\w+)\s+\|(.*$)") {
                      [pscustomobject]@{"Time"=$matches[1];'Type'=$matches[2];'Message'=$matches[3]}
                }
                else {[pscustomobject]@{"Time"=$Null;      'Type'=$null;      'Message'=$_}} } | out-Gridview
        }
    }
}
