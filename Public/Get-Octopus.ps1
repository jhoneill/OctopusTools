function Get-Octopus                        {
<#
    .SYNOPSIS
        Generic "Get an Octopus object" for those which don't need any complex handling.

    .DESCRIPTION
        Most things we want to work with have a Get-OctopusThing command which understands
        the specifics of that type.  But for a lot of types, it is also possible to use
        Get-Octopus -kind <<Thing>> -Key <<Thing-id or name>>.
        It Get-Octopus will try to provide tab completion for the Key field, if the kind is
        "thing" it assumes [space]/thingS/ will return object of that type with a name
        field to use in tab completion, and it assumes it can use name and ID in searching
        for whatever is specified in -key.

    .PARAMETER Kind
        The type of thing Environent, Project, etc. PowerShell will tab-complete suggested object types, but additional types may work.

    .PARAMETER Key
        The name or ID of the object. If Key is an object the function will look for .ID or .Name property to use. For some types PowerShell is able tab-complete names.

    .PARAMETER ExtraId
        If specified looks for an additional field for an ID before trying the one named ID.
        So if a project is passed as they key, and the kind specifies projectGroup -ExtraID ProejctGroupID will find the project group for the project

    .EXAMPLE
        $p = Get-Octopus  Project  Projects-123
        Gets an object -representing the project using its ID.
    .EXAMPLE
        Get-Octopus  Project  Banana,Cherry
        Gets two projects using their names -note that the names will tab-complete.
    .EXAMPLE
        Get-Octopus ProjectGroup -ExtraId projectgroupid $p
        This example use the project stored in Example #1, if this were passed into a
        request for a project group without specifying -ExtraID the function would look for a
        project group named "projects-123" which would fail.

#>
    [cmdletbinding()]
    param (
        [parameter(Mandatory=$true, Position=0)]
        [ArgumentCompleter({param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                        @( 'Environment', 'Feed', 'LibraryVariableSet', 'Lifecycle', 'Machine', 'Package', 'Project', 'ProjectGroup', 'Worker', 'WorkerPool').where({$_ -like "$wordToComplete*"})
        }) ]
        $Kind,

        [parameter(Mandatory=$false, Position=1)]
        [ArgumentCompleter({param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
            if ($fakeboundparameters.Kind) {(octoarglist $wordtoComplete "$($fakeBoundParameters.Kind)s").CompletionText}
        }) ]
        $Key,

        $ExtraId
    )
    if         (-not $PSBoundParameters.ContainsKey('Key') -or $null -eq $key )  {Invoke-OctopusMethod -PSType "Octopus$kind" -EndPoint "$Kind`s" -ExpandItems}
    foreach    ($k in $key) {
        if     (   $ExtraId -and                #ExtraID allows for e.g. getting a project-group when we were piped a project object
                $k.$ExtraId) {$k = $k.$ExtraId} #with a projectGroupID property  extra ID says use 'projectGroupID' if you see it,
        elseif ($k.id)       {$k = $k.id}       #Otherwise use ID if you see that.
        elseif ($k.Name)     {$k = $k.Name}     #Otherwise use a name property.
        if     ($k -match   "^$kind`s-"){       #So K either started as a string, or became a Name or ID. If it matches Objects-1234 it's an ID...
                Invoke-OctopusMethod -PSType "Octopus$kind" -EndPoint "$Kind`s/$k"
        }
        elseif ($k  -match '\*|\?' ) {         # If its a name with wild card characters get all items and do the filter in I.O.M
                Invoke-OctopusMethod -PSType  "Octopus$kind" -EndPoint "$Kind`s" -ExpandItems -Name $k
        }
        else    {                             # If its a name without wild cards use partial name to search
                $endpoint = "$kind`s?partialName=$([uri]::EscapeDataString($k))"
                Invoke-OctopusMethod -PSType  "Octopus$kind" -EndPoint $endpoint -ExpandItems -name $k
        }
    }
}
