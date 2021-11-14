<#
  .synopsis
    Tags the commit in an AzDO repository which is associated with the current process
  .description
    Orignally inspired by https://github.com/LiquoriChris/azuredevops-extension-tag-git-release
    It takes a name for an 'annotated tag' and the message for the tag, and an access token
    It discovers the repo and commit-ID from what it can find about the Octopus package in use
    If the tag name exists in the repo, it is moved to the current commit. If it doesn't exist it is created.
#>
[CmdletBinding(SupportsShouldProcess=$true)]
param (
   [Parameter(Mandatory=$true)]
   $ACCESSTOKEN,

   $TagName     = @("$OctopusProjectName/$OctopusReleaseNumber", $OctopusEnvironmentName),
   $Message     = "Created from Octopus Deploy",

   $FeedUri,    # = "https://pkgs.dev.azure.com/ORGANIZATION/_packaging/FEED/nuget/v3/index.json" ,
   $FeedId,     # = "feeds-1010"

   [switch]$NoClobber
)

$restParams     = @{
    Headers     = @{Authorization = "Basic " + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$ACCESSTOKEN"))  }
    ErrorAction = [System.Management.Automation.ActionPreference]::Stop
}
$postParms      = @{
    Method      = 'POST'
    ContentType = 'application/json'
}

#To find the repo and commmit to be tagged: either look in Octopus-deployment-changes, OR use feed details provided to find a package ...
if      (-not ($FeedUri -and $FeedId))   {
     #region if were weren't told a feed to go to, look in Octopus-deployment-changes, to find the URI of the commit.
    if      (-not  $OctopusParameters['Octopus.Deployment.Changes']) {
                Write-Warning "No feed information provided, and can't find Octopus.Deployment.Changes to get it."
                return
    }
    $odc    = ConvertFrom-Json $OctopusParameters['Octopus.Deployment.Changes']
    #the commit URI is written as http[s]://<<org>>@dev.azure.com/<<org>><<project>>/_git/<<repo>>/commit/<<commit id>>
    #We want to split the commit ID off and transform the rest into http[s]://dev.azure.com/<<org>><<project>>/_apis/git/repositories/<<repo>>
    if      ($odc.Commits -is [array] -and
             $odc.Commits[0].LinkUrl  -match '(https?://).*?@(.*?)/_git(/.*?)/commit/(\w+)$') {
                $repoUri    = $Matches[1] + $Matches[2] + '/_apis/git/repositories' +  $Matches[3]
                $commitid   = $Matches[4]
                Write-Verbose "Found commit in Octopus.Deployment.Changes repo $repoUri commit $commitid"
    }
    else    {
                Write-Warning 'Could not parse Octopus.Deployment.Changes.'
                return
    }
    #endregion
}
else    {
    #We got a feed ID so look for a package from that feed, and look for the the commit and repo in its AzDO provenance data
    #region Convert the URI used by the Octopus feed object to the URI we need to make REST calls to AzDO, and find what refers to a package from our feed
    if      (  $FeedUri -match '^(https?://)pkgs(.*)/_packaging/([^/]+)/nuget.*$'  ) {
                $uri            = $Matches[1] +'feeds' + $Matches[2] + '/_apis/packaging/feeds/' + $Matches[3] + "/packages"
    }
    else    {
                Write-warning "Feed URI '$FeedUri' looks wrong, it should look like 'https//PKGS.dev.azure.com/<<your org>>/_packaging/<<your feed>>/nuget....'."
                return
    }
    if      (  $FeedId  -notmatch '^feeds-\d+$') {
                Write-warning "Feed ID '$FeedId' looks wrong, it should look like 'feeds-1234'."
                return
    }
    else    {
                  $keyname      = $Octopusparameters.keys.where({ $_ -like "Octopus.Action.Package*.FeedId"  -and $Octopusparameters[$_] -eq $feedId})[0]
    }
    #endregion
    #region $Keyname should now hold "Octopus.Action.Package[something].FeedId" - use the related PackageID and version: first call the feed to find the package...
    if      (-not $keyname) {
                Write-Warning "Feed ID '$FeedId' doesn't seem to provide any packages in this step."
                return
    }
    else    {
                $packageId      = $Octopusparameters[($keyname -replace 'FeedId$','PackageId')]
                $packageVersion = $Octopusparameters[($keyname -replace 'FeedId$','PackageVersion')]
    }
    if      ( !($packageVersion -and $packageId)) {
                Write-warning "Could not find Package version and/or package ID"
    }
    else    {
                $package        = Invoke-RestMethod @restParams -Uri $uri  | Select-Object -ExpandProperty value |
                                        Where-Object -Property name -eq $packageID
    }
    #endregion
    #region The rest call uses a GUID for the pacakage and other for its version discover version guid and make the call to the get the provenance data
    if      ( ! $package) {
                Write-Warning "Could not find package '$packageId' at the feed"
                return
    }
    else    {
                $versionId      = $package.versions.Where({$_.version -eq $packageVersion}).id
                if (-not $versionId ) {
                         $versionid  = (Invoke-RestMethod @restParams -Uri $package.url ).versions.where({$_.version -eq $packageVersion}).id
                }
    }
    if      (!  $versionId) {
                Write-Warning "'$packageId' is a valid package, but version '$packageVersion' was not found."
                return
    }
    else    {
                $prov           = Invoke-RestMethod @restParams -Uri "$($package.url)/versions/$versionid/provenance"
    }
    #endregion
    #region Extract the repo-uri and commit0id from the provenance data
    if      (   $prov.provenance.data.'Build.SourceVersion' -and  $prov.provenance.data.'Build.Repository.Uri' -match '(https?://.*?)/_git(/.+?$)') {
                # other interesting things in the provennce data System.TeamProjectId , Build.BuildId, Build.BuildNumber ,  Build.DefinitionName
                #  Build.Repository.Name, Build.Repository.Provider, Build.Repository.Id , Build.SourceBranch, Build.SourceBranchName
                $commitid      = $prov.provenance.data.'Build.SourceVersion'
                $repoUri       = $Matches[1] +  '/_apis/git/repositories' +  $Matches[2]

                Write-Verbose "Found package '$packageId' version $packageVersion. Provence says BuildID $($prov.provenance.data.'Build.BuildID'), commit $commitid, repo: $repoUri "
    }
    else    {   Write-Warning 'Could not get the source version and repo details from the Provenance data'}
    #endregion
}
if      (-not ($repoUri -and $commitid)) {
                Write-Warning 'Could not discover the commit to tag and/or the repo it is found in.'
}

#Now we know what we tagging, we may want to attach multiple tags: if the tag already exists, uppate it and if it doesn't, create it
foreach ($name in $TagName) {
    $name                       = $name -replace  "^\.|^/|\.\.|//|@{|[~\^:?*\[\s\\]|\.$|/$" , "_"
    $existingRef                = (Invoke-RestMethod @restParams -Uri "$repoUri/refs?filterContains=/$name").value.where({$_.name -match "tags/$name`$"})
    if      ($existingRef.count -gt 1) {throw "Searching for 'tags/$name' returned more than one result"; return }
    if      ($existingRef -and $NoClobber) {
                Write-Warning "Tag '$name' exists and -Noclobber was specified. No Change will be made"
                return
    }
    elseif  ($existingRef) {
                $body           = ConvertTo-Json -Depth 2 -InputObject @( [ordered]@{
                    name            = $existingRef.name
                    oldObjectId     = $existingRef.objectId
                    newObjectId     = $commitid
                })
                $uri            = "$repoUri/refs?api-version=6.0"
                Write-Debug $body
                Write-Debug $uri
                if ($pscmdlet.ShouldProcess($name,"Move tag to a new commit, $commitid")) {
                    Invoke-RestMethod @restParams  @postParms -Uri $uri -Body $body | Select-Object -ExpandProperty value | Format-List | Out-String -Width 200
                }
    }
    else    {
                $body           = ConvertTo-Json -Depth 2 -InputObject ([ordered]@{
                    name            = $name
                    taggedObject    = @{objectId = $commitid}
                    message         = $Message
                })
                $uri            = "$repoUri/annotatedtags?api-version=6.0"
                Write-Debug  $body
                Write-Debug  $uri
                if ($pscmdlet.ShouldProcess($commitid,"Tag to with a new tag '$name'")) {
                    Invoke-RestMethod @restParams @postParms -Uri $uri -Body $body | Format-List | Out-String -Width 200
                }
   }
}
