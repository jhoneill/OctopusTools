function Invoke-OctopusMethod               {
<#
     .SYNOPSIS
        Handles all the common functions of making a rest API Call to Octopus Deploy.
    .DESCRIPTION
        Invokes a REST method It avoids the need to pass space and credentials to other commands
        When POSTING it can translate an object or hash-table into a JSON body.
        When GETTING it can expand the items collection and handle paged responses which
        need repeat calls to the server.
        In can filter results to those where Name (or ID) matches one of a set of values provided.
        And it can add a typename to enable PowerShell's formatting and type expansion.

    .PARAMETER EndPoint
        The API URI to call, the function will add http://host , /api/ space-id/ as needed.

    .PARAMETER PSType
        A type name, typically "OctpusThing", that is added to PSTypeNames. Formatting and type
        information can then recognize the item as an OctopusThing, and not just a PSCustomObject.

    .PARAMETER ExpandItems
        If specified, expands the Items returned by the REST API.

    .PARAMETER Name
        Filters GET operations based on the Name property.

    .PARAMETER First
        Returns the only the first n items.

    .PARAMETER Method
        GET , POST, PUT, DELETE etc.

    .PARAMETER Item
        An item to be converted to JSON in a PUT or POST request.

    .PARAMETER JSONBody
        If the item to be sent is already expressed as JSON it can be passed as a body instead of using the Item parameter.

    .PARAMETER ContentType
        Defaults to 'application/json; charset=utf-8', but can be overridden if the contents of JSONBody is something else.

    .PARAMETER RawParams
        If specified, even as an empty hash table, Invoke-WebRequest is used instead of Invoke-RestMethod adding parameters from the hash table to those Invoke-RestMethod would use
        The primary use is to return Raw JSON instead of a PS Custom Object

    .PARAMETER APIKey
        The Octopus API Key - found from the environment variable OctopusApiKey by default

    .PARAMETER OctopusUrl
        The URL of the Octopus server, without the "/API/etc" part of the URI - found from the environment variable OctopusUrl by default

    .PARAMETER SpaceId
        The Octopus space, NULL if the server doesn't support spaces,- found from the environment variable OctopusSpaceID default.
#>
    [Alias('iom')]
    [cmdletbinding(DefaultParameterSetName="Default")]
    param   (
        [Parameter(Position=0)]
        $EndPoint,

        [Parameter(ParameterSetName='Default')]
        [Parameter(ParameterSetName='JSON')]
        $PSType,

        [Parameter(ParameterSetName='Default')]
        [switch]$ExpandItems,

        [Parameter(ParameterSetName='Raw')]
        [Parameter(ParameterSetName='Default')]
        $Name,

        [alias('Take')]
        [int]$First,

        [Microsoft.PowerShell.Commands.WebRequestMethod]$Method= 'GET',

        [Parameter(ParameterSetName='Default')]
        $Item,

        [Parameter(ParameterSetName='Raw')]
        [Parameter(ParameterSetName='JSON')]
        [Alias('Body')]
        $JSONBody,

        [Parameter(ParameterSetName='Raw')]
        [Parameter(ParameterSetName='JSON')]
        $ContentType = 'application/json; charset=utf-8',

        [Parameter(ParameterSetName='Raw',Mandatory=$true)]
        [hashtable]$RawParams,

        $APIKey     = $env:OctopusApiKey,
        $OctopusUrl = $env:OctopusUrl,
        $SpaceId    = $env:OctopusSpaceID
    )
    begin   {
        $restParams = @{
            Headers = @{'X-Octopus-ApiKey' = $APIKey }
            Method  = $Method
        }
        if ($First) {$pageSize = $First}
        else        {$pageSize = 1000  } #you can tune this for 10K or 100 to suit
    }
    process {
        foreach ($e in $EndPoint) {
            #strip leading and trailing / from uri and endpoint so they join
            #if endpoint is not "api/something" make it api/thing or api/space-id/thing
            #Specify an upper limit for how many we will get when expanding items
            $uri =  $OctopusUrl -replace '/$',''
            $e   =  $e -replace '^/',''
            if     ($e -match '^api')        {$uri += "/$e" }
            elseif ($SpaceId)                {$uri += "/api/$SpaceId/$e"}
            else                             {$uri += "/api/$e"}
            if    (($Name -or $ExpandItems) -and
                    $uri -notmatch '[?&]take=\d+' -and
                    $Method -eq 'GET') {
                if ($uri -notmatch '\?')     {$uri += "?take=$pageSize"}
                else                         {$uri += "&take=$pageSize"}
            }
            try      {
                if ($Item)     {$restParams['body'] = $Item | ConvertTo-Json -Depth 10}
                if ($JSONBody) {$restParams['body'] = $JSONBody }
                if ($restParams['body'])      {
                                $restParams['ContentType'] = $ContentType
                                Write-Debug $restParams.body
                }
                if ($RawParams) {
                    (Invoke-WebRequest @restParams -uri $uri @RawParams).content
                }
                else   {
                    $result = Invoke-RestMethod @restParams -Uri $uri
                    if (-not $Name -and -not $ExpandItems) {
                        if  ($PSType) {foreach ($r in $result) {$r.pstypeNames.add($PSType)}}
                        return         $result
                    }
                    else  {
                        $items = $result.items
                        if  ($result.NumberOfPages -gt 1 -and -not $First -and $uri -notmatch '[?&]skip=\d+' -and $uri -match "[?&]take=$pageSize")  {
                            1..$result.LastPageNumber | ForEach-Object {
                                $NumberToSkip = $pageSize * $_
                                $items += (Invoke-RestMethod @restParams -Uri "$uri&skip=$NumberToSkip").items
                            }
                        }
                        if  ($PSType) {foreach ($i in $items) {$i.pstypenames.add($PSType)}  }
                        if  ($Name)   {return $items.where({foreach ($n in $Name) {if ($_.name -like $n -or $_.id -eq $n) {$true}}})}
                        else          {return $items }
                    }
                }
            }
            catch    {
                if     ($_.Exception.Response.StatusCode -eq 401) {
                        Write-Error "Unauthorized error returned from $uri, please verify API key and try again"
                }
                elseif ($_.Exception.Response.statusCode -eq 403) {
                        Write-Error "Forbidden error returned from $uri, please verify API key and try again"
                }
                else {  Write-Error "Error calling $uri $($_.Exception.Message) StatusCode: $($_.Exception.Response.StatusCode )" }
                throw   $_.Exception
            }
        }
    }
}
