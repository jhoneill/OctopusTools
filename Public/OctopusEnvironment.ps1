function New-OctopusEnvironment             {
[cmdletbinding(SupportsShouldProcess=$true)]
<#
    .links
        https://Octopus.com/docs/Octopus-rest-api/examples/environments/add-environments
#>
    param   (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty]
        $Name
    )
    begin   {
        $environmentList = Get-OctopusEnvironment
    }
    process {
        foreach ($n in $name) {
            if ($environmentList.name -contains $n) {
                Write-Warning "Environment '$environment' already exists. Nothing to create"
            }
            elseif ($PSCmdlet.ShouldProcess($n,'Create Octopus Environment')) {
                $response = Invoke-OctopusMethod -EndPoint environments -Method Post -Item  @{Name = $n} -PSType OctopusEnvironment
                Write-Verbose "New Environment '$n', Id='$($response.Id)'"
                return $response
            }
        }
    }
}
