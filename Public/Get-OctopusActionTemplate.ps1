function  Get-OctopusActionTemplate         {
    <#
    .SYNOPSIS
        Returns one or more Action templates, or the actions which use them

    .PARAMETER ActionTemplate
        The name or ID of an Action template, or an object representing an Action template. If nothing is specified all templates will be included

    .PARAMETER BuiltIn
       Restricts the search to only built-in templates.

    .PARAMETER Custom
        Restricts the search to only Custom templates.

    .PARAMETER Community
        Restricts the search to only Community template templates.

    .PARAMETER Usage
        When specified with a template, gets the actions which use the template

    .EXAMPLE
        ps > Get-OctopusActionTemplate "SQL server*" , "MySQL*"

        Gets all templates with names that start either 'SQL Server' or 'MySQL'

    .EXAMPLE
        ps >  Get-OctopusActionTemplate -Custom "*https*" | ForEach-Object {$_.UseDetails()  | export-excel -path Actiontemplates.xlsx -WorksheetName $_.id }

        Gets all custom (user created) templates with a name containing HTTPS and exports the project actions where they are used to Excel
       The .Usage() script method of a template lists the actions based on the template, with the step and deployment process each belongs to and the version of the template in use.
       The .UseDetails() script method extends usage to give show the roles the step applies to, worker pools where it runs and the parameters it is called with.

    .NOTES
    General notes
    #>
    [cmdletbinding(DefaultParameterSetName='Default')]
    param   (
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        [Parameter(Position=0,ValueFromPipeline=$true,ParameterSetName='Default')]
        [Parameter(Position=0,ValueFromPipeline=$true,ParameterSetName='BuiltIn')]
        [Parameter(Position=0,ValueFromPipeline=$true,ParameterSetName='Custom')]
        [Parameter(Position=0,ValueFromPipeline=$true,ParameterSetName='Community')]
        [Parameter(Position=0,ValueFromPipeline=$true,ParameterSetName='Usage')]
        [Alias('Id','Name')]
        $ActionTemplate = '*',

        [Parameter(ParameterSetName='BuiltIn')]
        [switch]$BuiltIn,
        [Parameter(ParameterSetName='Custom')]
        [switch]$Custom,
        [Parameter(ParameterSetName='Community')]
        [switch]$Community,
        [Parameter(ParameterSetName='Usage')]
        [switch]$Usage
    )
    begin   {$results = @()}
    process {
    #add -usage
        if         (-not  $ActionTemplate) {
                    $results = Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint actiontemplates/search
        }
        foreach    ($a in $ActionTemplate) {
            if     ($a.ID  ) {$a = $a.Id}
            elseif ($a.Name) {$a = $a.Name}
            if     ($a    -match '^ActionTemplates-\d+$') {
                    $singleResult = Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint "ActionTemplates/$a"
            }
            elseif ($a    -match '^CommunityActionTemplates-\d+$') {
                    $singleResult = Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint "CommunityActionTemplates/$a"  -SpaceId $Null
            }
            elseif ($a -notmatch '\*|\?' -and $Custom)    {
                    $endpoint = "ActionTemplates?partialName=$([uri]::EscapeDataString($a))"
                    $singleResult = Invoke-OctopusMethod -EndPoint $endpoint -ExpandItems -name $a -PSType "OctopusActionTemplate"
            }
            elseif ($a -notmatch '\*|\?' -and $Community) {
                    $endpoint = "CommunityActionTemplates?partialName=$([uri]::EscapeDataString($a))"
                    $singleResult = Invoke-OctopusMethod -EndPoint $endpoint -ExpandItems -SpaceId $Null -Name $a -PSType "OctopusActionTemplate"
            }
            else   {
                    #search self-expands items but they're no the full item!
                    $results += Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint actiontemplates/search | Where-Object -Property Name -Like $a
            }

            if     ($singleResult -and $Usage) {$singleResult.Usage() }
            elseif ($singleResult)             {$singleResult}
        }
    }
    end    {
        if      ($Community) {$results = $results | Where-Object {$_.id  -like 'CommunityActionTemplates-*'} }
        elseif  ($Custom)    {$results = $results | Where-Object {$_.id  -like 'ActionTemplates-*'} }
        elseif  ($BuiltIn)   {$results = $results | Where-Object {$null -eq $_.id } }
        foreach ($r in ($results  | Sort-Object @{e={$_.id -replace '\d+','' }},Name ) ) {
            if     (-not $r.id)           {$r}
            elseif ($usage -and $r.usage) {$r.usage()}
            else   {
                    Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint ($r.links.logo -replace  "/logo" )
            }
        }
    }
}
