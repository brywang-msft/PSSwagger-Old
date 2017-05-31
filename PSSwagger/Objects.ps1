class InfoContext : OpenAPI.NET.Modeler.DataModelBase
{
    [hashtable]$InfoDict
    InfoContext($InfoDict)
    {
        $this.InfoDict = $InfoDict
    }
    [void] AcceptChild([object]$child, [string]$key)
    {
        Write-Host "AcceptChild: $key" -BackgroundColor DarkGreen
        Write-Host "child: $($child.GetType().Name)" -BackgroundColor DarkGreen
        if ($child -is [DictionaryContext])
        {
            foreach ($kvp in $child.Dictionary.GetEnumerator())
            {
                Write-Host "$($kvp.Key) = $($kvp.Value)" -BackgroundColor DarkGreen
                $this.InfoDict[$kvp.Key] = $kvp.Value
            }
        }
    }
}
class DictionaryContext : OpenAPI.NET.Modeler.DataModelBase
{
    [hashtable]$Dictionary
    DictionaryContext($Dictionary)
    {
        $this.Dictionary = $Dictionary
    }
}
class DefinitionFunctionDetailsContext : OpenAPI.NET.Modeler.DataModelBase
{
    [hashtable]$DefinitionFunctionDetails
    DefinitionFunctionDetailContext([hashtable]$DefinitionFunctionDetails)
    {
        $this.DefinitionFunctionDetails = $DefinitionFunctionDetails
    }
    [void] AssignIfKeyMissing([string]$key,[object]$val) {
        if (-not $this.DefinitionFunctionDetails.ContainsKey($key)) {
            $this.DefinitionFunctionDetails[$key] = $val
        }
    }
}
class ParameterDetailsContext : OpenAPI.NET.Modeler.DataModelBase
{

}
class NameHelpers
{
    static [string] GetName([OpenAPI.NET.Parser.SpecificationObject]$spec) {
        if($spec.ReferenceObject -eq $null) { 
            return $spec.Key
        } else { 
            return $spec.ReferenceObject.Key
        }
    }
    static [string] GetPascalCasedString($Name) {
        if($Name) {
            $Name = [NameHelpers]::RemoveSpecialCharacter($Name)
            $startIndex = 0
            $subStringLength = 1

            return $($Name.substring($startIndex, $subStringLength)).ToUpper() + $Name.substring($subStringLength)
        }
        return $null
    }
    static [string] RemoveSpecialCharacter([string]$Name)
    {
        $pattern = '[^a-zA-Z0-9]'
        return ($Name -replace $pattern, '')
    }
}
class PSTypeHelpers
{
    static [string] GetTypeFromSchemaObject([OpenAPI.NET.Parser.v2.SchemaObject]$spec,[string]$namespace, [string]$models, $CSharpCodeNamer)
    {
        $DefinitionTypeNamePrefix = "$namespace.$models"
        if ($spec.Type -eq $null -or $spec.Type -eq "object") {
            $typeName = "$DefinitionTypeNamePrefix.$($CSharpCodeNamer.GetTypeName([NameHelpers]::GetName($spec)))"
        } else {
            $typeName = [PSTypeHelpers]::GetPSType($spec.Type,$spec.Format,$true)
        }

        # TODO: This is actually only true if the property is Required
        # If not, and x-ms-enum exists, x-ms-enum is honored
        if ($spec.Enum -ne $null -and $spec.Enum.Count -gt 1 -and $spec.Extensions.ContainsKey("x-ms-enum") -and (-not $spec.Extensions["x-ms-enum"].ModelAsString)) {
            #Write-Host "x-ms-enum enum found"
            $enumName = $CSharpCodeNamer.GetTypeName($spec.Extensions["x-ms-enum"].Name)
            $typeName = "$DefinitionTypeNamePrefix.$enumName"
        } elseif ($spec.Format -ne $null -and $spec.Format -as [Type]) {
            $typeName = $spec.Format
        } elseif ($spec.Type -eq "array") {
            if ($spec.Items.Type -eq $null -or $spec.Items.Type -eq "object") {
                $typeName = "$DefinitionTypeNamePrefix.$($CSharpCodeNamer.GetTypeName([NameHelpers]::GetName($spec.Items)))[]"
            } else {
                $typeName = "$([PSTypeHelpers]::GetPSType($spec.Items.Type,$spec.Items.Format,$false))[]"
            }
        } elseif ($spec.AdditionalProperties -ne $null -and $spec.Properties -eq $null) {
            # AutoRest generates this type of object as a Dictionary<string, T>
            # TODO: Original parsing logic does this: "System.Collections.Generic.Dictionary[[$AdditionalPropertiesType],[$AdditionalPropertiesType]]"
            # Is that right??
            #Write-Host "AP.Type: $($spec.AdditionalProperties.Type)"
                
            if ($spec.AdditionalProperties.Type -eq $null -or $spec.AdditionalProperties.Type -eq "object") {
                #Write-Host "AP.GetName: $($this.GetName($spec.AdditionalProperties))"
                $AdditionalPropertiesType = $CSharpCodeNamer.GetTypeName([NameHelpers]::GetName($spec.AdditionalProperties))
            } else {
                $AdditionalPropertiesType = [PSTypeHelpers]::GetPSType($spec.AdditionalProperties.Type,$spec.AdditionalProperties.Format,$false)
            }
            $typeName = "System.Collections.Generic.Dictionary[[string],[$AdditionalPropertiesType]]"
        }
        #Write-Host "Type: $typeName"
        return $typeName
    }
    static [string] GetPSType([string]$specParameterType, [string]$specParameterFormat, [bool]$useSwitchType) {
        $parameterType = $specParameterType
        switch ($specParameterType) {
            'Boolean' {
                if ($useSwitchType) {
                    $parameterType = 'switch'
                } else {
                    $parameterType = 'bool'
                }
                break
            }

            'Integer' {
                if($specParameterFormat) {
                    $parameterType = $specParameterFormat
                }
                else {
                    $parameterType = 'int64'
                }
                break
            }

            'Number' {
                if($specParameterFormat) {
                    $parameterType = $specParameterFormat
                }
                else {
                    $parameterType = 'double'
                }
                break
            }
        }
        return $parameterType
    }
}
class ParameterBuildHelpers
{
    static [ParameterDetailsContext] CreateFromSchemaObject([OpenAPI.NET.Parser.v2.SchemaObject]$spec)
    {
        $parameterName = [NameHelpers]::GetPascalCasedString($spec.Key)
        $ParameterDetails = @{}
        $ext = $spec.GetExtension("x-ms-client-name")
        if ($ext) {
            $parameterName = [NameHelpers]::GetPascalCasedString($ext)
        }
        $parameterType = [PSTypeHelpers]::GetTypeOfSchemaObject($spec)
        $IsParamMandatory = '$false'
            # $parameterType = $this.GetTypeOfSchemaObject($spec)
            # $IsParamMandatory = '$false'
            # if ($phase.Parent.HasParent([OpenAPI.NET.Parser.v2.SchemaObject])) {
            #     #Write-Host "Required: $($phase.Parent.Parent.CurrentSpecObject.Required)"
            #     if ($phase.Parent.Parent.CurrentSpecObject.Required -ne $null -and $phase.Parent.Parent.CurrentSpecObject.Required -contains $parameterName) {
            #         $IsParamMandatory = '$true'
            #     }
            # }
            # $ValidateSetString = $null
            # $ParameterDescription = $spec.Description

            # if ($spec.Enum -ne $null) {
            #     # Process enum if x-ms-enum.ModelAsString is set to true, or there's no x-ms-enum extension
            #     if ((-not $spec.ContainsKey("x-ms-enum")) -or $spec.Extensions["x-ms-enum"].ModelAsString) {
            #         $EnumValues = $spec.Enum | ForEach-Object {$_ -replace "'","''"}
            #         $ValidateSetString = "'$($EnumValues -join "', '")'"
            #     }
            # }
            # #Write-Host "ValidateSetString: $ValidateSetString"
            # $ParameterDetails['Name'] = $parameterName
            # $ParameterDetails['Type'] = $parameterType
            # $ParameterDetails['ValidateSet'] = $ValidateSetString
            # $ParameterDetails['Mandatory'] = $IsParamMandatory
            # $ParameterDetails['Description'] = $ParameterDescription

            # #Write-Host "Final ParameterDetails: $($ParameterDetails | Out-String)"

            # if ($parameterType) {
            #     #Write-Host "Add ParameterDetails to [$objectName]['ParametersTable'][$parameterName]"
            #     $FunctionDetails['ParametersTable'][$parameterName] = $ParameterDetails
            #     # The original logic has that if there's only one property, AutoRest won't generate a model - which doesn't seem to be true!
            #    # if ($this.GetHashtableKeyCount($FunctionDetails['ParametersTable']) -gt 1) {
            #      # This is only a model if it isn't anonymous
            #      if (-not $FunctioNDetails.ContainsKey('IsAnonymous') -or -not $FunctionDetails['IsAnonymous']) {
            #          $FunctionDetails['IsModel'] = $true
            #      }
            #     #}
            # }
    }
}