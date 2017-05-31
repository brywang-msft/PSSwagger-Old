class TestDefinitionsBuilder : OpenAPI.NET.Modeler.SpecificationObjectVisitor
{
    [hashtable]$PathFunctionDetails
    [hashtable]$SwaggerDict
    [hashtable]$SwaggerMetaDict
    [hashtable]$DefinitionFunctionsDetails
    [hashtable]$ParameterGroupCache
    [hashtable]$MetadataDictionary
    [object]$CSharpCodeNamer
    TestDefinitionsBuilder($PathFunctionDetails, $SwaggerDict, $SwaggerMetaDict, $DefinitionFunctionsDetails, $ParameterGroupCache, $metadataDictionary, $cSharpCodeNamer)
    {
        $this.PathFunctionDetails = $PathFunctionDetails
        $this.SwaggerDict = $SwaggerDict
        $this.SwaggerMetaDict = $SwaggerMetaDict
        $this.DefinitionFunctionsDetails = $DefinitionFunctionsDetails
        $this.ParameterGroupCache = $ParameterGroupCache
        $this.MetadataDictionary = $metadataDictionary # This stuff should come from our new metadata extensions
        $this.CSharpCodeNamer = $cSharpCodeNamer

        $this.Dispatches([OpenAPI.NET.Parser.v2.DocumentRoot])
        $this.Dispatches([OpenAPI.NET.Parser.v2.DefinitionsObject])
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.DefinitionsObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        $this.SwaggerDict['Definitions'] = @{}
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.SchemaObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        if ($phase.HasParent([OpenAPI.NET.Parser.v2.DefinitionsObject]))
        {
            # Create a DefinitionFunctionsDetails entry
            $details = @{}
            $Name = $this.CSharpCodeNamer.GetTypeName($spec.Key)
            $details['Name'] = $Name
            if ($this.DefinitionFunctionsDetails.ContainsKey($details['Name'])) {
                $details = $this.DefinitionFunctionsDetails[$details['Name']]
            }
            $context = New-Object -TypeName DefinitionFunctionDetailsContext -ArgumentList $details
            $context.AssignIfKeyMissing('Description',$FunctionDescription)
            $context.AssignIfKeyMissing('ParametersTable',@{})
            if ($spec.Discriminator) {
                $context.DefinitionFunctionDetails['ParametersTable'][$spec.Discriminator] = @{
                    Discriminator = $true
                }
            }
            $context.AssignIfKeyMissing('Type',[PSTypeHelpers]::GetTypeFromSchemaObject($spec))
            $context.AssignIfKeyMissing('IsModel',$false)
            $context.AssignIfKeyMissing('IsUsedAs_x_ms_client_flatten',$false)
            return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($context)
        } elseif ($phase.HasParent([OpenAPI.NET.Parser.v2.SchemaObject]))
        {
            if ($spec.Key -eq "AllOf")
            {
                # Continue onto children
                # The parent DefinitionFunctionDetailContext should still be on the stack
                return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
            }
        } elseif ($phase.HasParent([OpenAPI.NET.Parser.v2.PropertiesObject])) 
        {
            if (($spec.Extensions.ContainsKey("x-ms-client-flatten")) -and ($true -eq $spec.Extensions["x-ms-client-flatten"])) {
                # If x-ms-client-flatten is set and another object is being referenced, set IsUsedAs_x_ms_client_flatten = true
                if ($spec.ReferenceObject -ne $null) {
                    $refName = $this.GetName($spec.ReferenceObject)
                    #Write-Host "$refName is a flatten target"
                    $FunctionDetails = @{
                        Name = $refName
                    }
                    if ($this.DefinitionFunctionsDetails.ContainsKey($FunctionDetails['Name'])) {
                        $FunctionDetails = $this.DefinitionFunctionsDetails[$FunctionDetails['Name']]
                    }
                    $FunctionDetails['IsUsedAs_x_ms_client_flatten'] = $true
                    $this.DefinitionFunctionsDetails[$FunctionDetails['Name']] = $FunctionDetails
                }
                # Continue onto children
                # The correct DefinitionFunctionDetailContext should still be on top
                return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
            }
            # $helpers = New-Object -TypeName ParameterBuildHelpers
            # $context = $helpers.CreateFromSchemaObject
            # DefinitionFunctionDetailContext will accept the ParameterDetailContext child and add the parameter to its table

            # $parameterName = $this.GetPascalCasedString($spec.Key)
            # $ParameterDetails = @{}
            # $FunctionDetails = @{
            #     Name = $objectName
            #     ParametersTable = @{}
            # }
            # if ($this.DefinitionFunctionsDetails.ContainsKey($FunctionDetails['Name'])) {
            #     $FunctionDetails = $this.DefinitionFunctionsDetails[$FunctionDetails['Name']]
            # }

            # if ($FunctionDetails['ParametersTable'].ContainsKey($parameterName)) {
            #     $ParameterDetails = $this.DefinitionFunctionsDetails[$objectName]['ParametersTable'][$parameterName]
            # }
            # if ($spec.Extensions.ContainsKey("x-ms-client-name")) {
            #     $parameterName = $this.GetPascalCasedString($spec.Extensions["x-ms-client-name"])
            # }
            # #Write-Host "Found parameter '$parameterName' for object '$objectName'" -BackgroundColor DarkMagenta
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

            # $this.DefinitionFunctionsDetails[$FunctionDetails['Name']] = $FunctionDetails

            # # Stop here so we don't process inner schema objects any further
            # return [OpenAPI.NET.Modeler.ModelBuildResult]::Stop($null)
        }

        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
}