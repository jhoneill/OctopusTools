
function Find-OctopusObject                 {
    <#
        .Synopsis Simple keyword search. Requires a version of Octopus with Spaces support.
    #>
    param (
        $Keyword
    )
    if (-not $env:OctopusSpaceID) {
            Write-warning "Space should be set by Connect-Octopus before using this command"
    }
    else {
            Invoke-OctopusMethod "search?keyword=$Keyword"
    }
}

function  Update-OctopusObject              {
<#
    .synopsis
        Updater for those object-types which use the standard process
    .description
        Most Octopus objects have a .Links Property with a .self member
        and many that support updates do so by modifying the object,
        converting it [back] to JSON and calling the .links.self URI with
        a PUT request and the JSON representation of the desired state.
        This works for those
#>
    [cmdletbinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
    param (
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
        $InputObject,

        [switch]$Force,

        [Parameter(DontShow=$true)]
        [ActionPreference]$VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')
    )
    process {
        foreach ($obj in $InputObject) {
            if (-not $obj.links.self) {
                Write-Warning "Object does not have a 'self' Link to post updates to."
                continue
            }
            $pstype = $obj.pstypenames.where({$_ -like 'Octopus*'}) | Select-Object -First 1
            if       ($obj.Name) {$displayname = $obj.Name}
            elseif   ($obj.ID)   {$displayname = $obj.id}
            else                 {$displayname = 'Unnamed'}
            if ($displayName  -eq 'Unnamed' -or -not $pstype) {
                Write-Warning "Object does not have the expected attributes, update may fail."
            }
            if ($Force -or $PSCmdlet.ShouldProcess($displayName,  "Update $pstype object")) {
                Invoke-OctopusMethod -Method Put -PSType $PStype -EndPoint $obj.links.Self -Item $obj
            }
        }
    }
}

$Script:IDLookup = @{}
function Convert-OctopusID                  {
    param (
    [Parameter(Position=0,ValueFromPipeline=$true)]
    $id
    )
    #We have a script-scoped hash table IDLookup - it has 2 of kinds entry
    # .Thing       is a nested hash table of ID ==> name for that kind of thing
    # .Time-Thing  is a time stamp for we last populated Thing
    # If .Thing is missing, or the time looks too old we refresh, or we we get a miss we [re]fill the data
    # Then we can look for IDLookup.Thing.ID
    process {
        #if it doesn't look like a things-1234 ID give up now
        if ($id -notmatch  '^(\w+s)(-\d+$)') {$id}
        else {
            $kind = $Matches[1]
            if ((-not $Script:IDLookup[$kind]) -or (-not $Script:IDLookup[$kind][$id]) -or [datetime]::Now.AddHours(-1) -gt $Script:IDLookup["Time-$kind"]) {
                $Script:IDLookup["Time-$kind"] = [datetime]::Now
                $Script:IDLookup[$kind]        = @{}
                Invoke-OctopusMethod "$kind/all" -ErrorAction SilentlyContinue -Verbose:$false | ForEach-Object {
                    $Script:IDLookup[$kind][$_.id] = $_.name
                }
            }
            if ($Script:IDLookup[$kind] -and $Script:IDLookup[$kind][$id]) {$Script:IDLookup[$kind][$id]}
            else {$id}
        }
    }
}
