function Undo-JsonConversion {
<#
Adapted from something of Adam Bartram's, see https://4sysops.com/archives/convert-json-to-a-powershell-hash-table/
#>
    [OutputType('hashtable')]
    param ([Parameter(ValueFromPipeline)]$InputObject)
    process {
        <#Called recursively to expand the result of convertFrom-Json to a hash table, possible inputs we see
          1. A null (empty property) return null
          2. A number, boolean, string, return it.
          3. A psobject. Make its property names hashtable keys and their values the corresponding hash table values
          4. An array, expand its members and return them as an array.
          For anything else issue a warning, any record-type/object/hash-table encoded to JSON converts to a PSObject.
        #>
        if ($null -eq  $InputObject -or $InputObject -is [ValueType] -or $InputObject -is [string]) {
           return $InputObject
        }
        elseif        ($InputObject -is [System.Collections.IEnumerable] ) {
            Write-Output -NoEnumerate @( $InputObject | ConvertTo-Hashtable )
        }
        elseif        ($InputObject -is [psobject]) {
            $hash = @{}
            $InputObject.PSObject.Properties.where({$_.MemberType -eq 'NoteProperty'}) | ForEach-Object {
                $hash[$_.Name] = ConvertTo-Hashtable $_.Value
            }
            $hash
        }
        else {
            Write-Warning "$InputObject was not handled."
        }
    }
}
