class TestModelBuilder : OpenAPI.NET.Modeler.SpecificationObjectVisitor
{
    [hashtable]$PathFunctionDetails
    [hashtable]$SwaggerDict
    [hashtable]$SwaggerMetaDict
    [hashtable]$DefinitionFunctionsDetails
    [hashtable]$ParameterGroupCache
    [hashtable]$MetadataDictionary
    [object]$CSharpCodeNamer
    TestModelBuilder($PathFunctionDetails, $SwaggerDict, $SwaggerMetaDict, $DefinitionFunctionsDetails, $ParameterGroupCache, $metadataDictionary, $cSharpCodeNamer)
    {
        $this.PathFunctionDetails = $PathFunctionDetails
        $this.SwaggerDict = $SwaggerDict
        $this.SwaggerMetaDict = $SwaggerMetaDict
        $this.DefinitionFunctionsDetails = $DefinitionFunctionsDetails
        $this.ParameterGroupCache = $ParameterGroupCache
        $this.MetadataDictionary = $metadataDictionary # This stuff should come from our new metadata extensions
        $this.CSharpCodeNamer = $cSharpCodeNamer

        $this.Dispatches([OpenAPI.NET.Parser.v2.DocumentRoot])
        $this.Dispatches([OpenAPI.NET.Parser.v2.InfoObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.ContactObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.LicenseObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.DefinitionsObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.SchemaObject])
        $this.Dispatches([OpenAPI.NET.AutoRestExtensions.CodeGenerationSettings])
        $this.Dispatches([OpenAPI.NET.Parser.v2.PropertiesObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.PathsObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.PathItemObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.OperationObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.ParameterObject])
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Visit([OpenAPI.NET.Parser.SpecificationObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        return $this.Accept($spec, $phase)
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.DocumentRoot]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.InfoObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        $this.SwaggerDict['Info'] = @{
            DefaultCommandPrefix = $this.MetadataDictionary['DefaultCommandPrefix']
            ModuleName = $this.MetadataDictionary['ModuleName']
            Models = "Models"
            Version = $this.MetadataDictionary['ModuleVersion']
            CodeOutputDirectory = ''
            # For when these child objects don't exist
            ContactName = $null
            ProjectUri = $null
            ContactEmail = $null
            LicenseUri = $null
            LicenseName = $null
        }

        if ($spec.Version) {
            $this.SwaggerDict['Info']['InfoVersion'] = $spec.Version
        } else {
            $this.SwaggerDict['Info']['InfoVersion'] = '1-0-0'
        }
        $this.SwaggerDict['Info']['InfoTitle'] = $spec.Title
        $this.SwaggerDict['Info']['NameSpace'] = "Microsoft.PowerShell.$($this.MetadataDictionary['ModuleName']).v$(($this.MetadataDictionary['ModuleVersion']) -replace '\.','')"

        if (-not $this.SwaggerDict['Info']['InfoName'])  {
            $this.SwaggerDict['Info']['InfoName'] = ($spec.Title -replace '[^a-zA-Z0-9_]','')
        }

        if ($this.SwaggerDict['Info']['NameSpace'].Split('.', [System.StringSplitOptions]::RemoveEmptyEntries) -contains $this.SwaggerDict['Info']['InfoName']) {
            $this.SwaggerDict['Info']['InfoName'] = $this.SwaggerDict['Info']['InfoName'] + 'Client'
        }

        $this.SwaggerDict['Info']['Description'] = $spec.Description
        $this.SwaggerDict['Info']['Models'] = "Models"
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.ContactObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        $this.SwaggerDict['Info']['ContactName'] = $spec.Name
        $this.SwaggerDict['Info']['ProjectUri'] = $spec.Url
        $this.SwaggerDict['Info']['ContactEmail']= $spec.Email
        
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.LicenseObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        $this.SwaggerDict['Info']['LicenseUri'] = $spec.Url
        $this.SwaggerDict['Info']['LicenseName'] = $spec.Name
        
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.DefinitionsObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        # TODO: We had a skeleton OnComplete action here, but what was it supposed to do?
        $this.SwaggerDict['Definitions'] = @{}
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [void] AssignIfKeyMissing([hashtable]$dict,[string]$key,[object]$val) {
        if (-not $dict.ContainsKey($key)) {
            $dict[$key] = $val
        }
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.SchemaObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        if ($phase.HasParent([OpenAPI.NET.Parser.v2.DefinitionsObject]))
        {
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
            $context.AssignIfKeyMissing('Type',$this.GetTypeOfSchemaObject($spec))
            $context.AssignIfKeyMissing('IsModel',$false)
            $context.AssignIfKeyMissing('IsUsedAs_x_ms_client_flatten',$false)
            return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($context)
            # $FunctionDescription = ""
            # if ($spec.Description) {
            #     $FunctionDescription = $spec.Description
            # }

            # $this.AssignIfKeyMissing($details,'Description',$FunctionDescription)
            # $this.AssignIfKeyMissing($details,'ParametersTable',@{})
            # if ($spec.Discriminator) {
            #     $details['ParametersTable'][$spec.Discriminator] = @{
            #         Discriminator = $true
            #     }
            # }
            # $this.AssignIfKeyMissing($details,'Type',$this.GetTypeOfSchemaObject($spec))
            # <#if ($spec.Properties -ne $null -and $spec.Properties.Keys.Count -gt 1) {
            #     $details['IsModel'] = $true
            # } else {
            #     $details['IsModel'] = $false
            # }#>
            # $this.AssignIfKeyMissing($details,'IsModel',$false)
            # $this.AssignIfKeyMissing($details,'IsUsedAs_x_ms_client_flatten',$false)
            # $this.DefinitionFunctionsDetails[$Name] = $details
            # #Write-Host "Definition: $Name = $($details | Out-String)" -BackgroundColor DarkBlue

            # # ModelContext helps support the x-ms-client-flatten scenario
            # # Tells child objects which object is being built right now
            # $context = New-Object -TypeName OpenAPI.NET.Modeler.ModelContext
            # $context.Info = $Name
            # return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($context)
        } elseif ($phase.HasParent([OpenAPI.NET.Parser.v2.SchemaObject]))
        {
            if ($spec.Key -eq "AllOf")
            {
                # TODO: Check if this isn't an object type, cause we don't know how to handle that yet
                if ($spec.ReferenceObject -eq $null)
                {
                    $spec.Key = [Guid]::NewGuid()
                    $details = @{}
                    $details['Name'] = $this.CSharpCodeNamer.GetTypeName($spec.Key)
                    $details['ParametersTable'] = @{}
                    $details['IsModel'] = $false
                    $details['IsAnonymous'] = $true
                    $details['IsUsedAs_x_ms_client_flatten'] = $false
                    $details['GenerateDefinitionCmdlet'] = $false
                    $details['GenerateFormat'] = $false
                    $this.DefinitionFunctionsDetails[$details['Name']] = $details
                }
                
                # Copy this schema object's properties into the parent schema object's parameters table
                # The parent object was already processed, so it exists in DefinitionFunctionsDetails
                # But to get this schema object's properties, we have two options:
                # A) Manually process the PropertiesObject child here
                #       This seems simpler than (B)
                # B) Create the DefinitionFunctionsDetails object. In Accept(PropertiesObject), fill in the ParametersTable.
                #       This returns a ModelContext with OnComplete that copies this ParameterTable into the parent table
                #       This would also account for the basic case as well (a definition object with properties)
                $context = New-Object -TypeName OpenAPI.NET.Modeler.ModelContext
                $context.Info = $this.CSharpCodeNamer.GetTypeName($this.GetName($phase.CurrentSpecObject))
                $context.Properties["CodeNamer"] = $this.CSharpCodeNamer
                $context.Properties["CurrentSpecObject"] = $phase.CurrentSpecObject
                $context.Properties["ParentSpecObject"] = $phase.Parent.CurrentSpecObject
                $context.Properties["CurrentSpecObjectName"] = $this.CSharpCodeNamer.GetTypeName($this.GetName($phase.CurrentSpecObject))
                $context.Properties["ParentSpecObjectName"] = $this.CSharpCodeNamer.GetTypeName($this.GetName($phase.Parent.CurrentSpecObject))
                $context.Properties["DefinitionFunctionsDetails"] = $this.DefinitionFunctionsDetails
                $onComplete = [Action[OpenAPI.NET.Modeler.ModelContext]]{param($c)
                    #Write-Host "OnComplete" -BackgroundColor DarkRed
                    $currentObjectName = $c.Properties["CurrentSpecObjectName"]
                    $parentObjectName = $c.Properties["ParentSpecObjectName"]
                    $DefinitionFunctionsDetails = $c.Properties['DefinitionFunctionsDetails']
                    #Write-Host "Now we copy $($currentObjectName)'s parameters into $($parentObjectName)'s parameters" -BackgroundColor DarkRed
                    foreach ($kvp in $DefinitionFunctionsDetails[$currentObjectName]['ParametersTable'].GetEnumerator()) {
                        #Write-Host "Copy '$($kvp.Key)' = $($kvp.Value | Out-String)"
                        $DefinitionFunctionsDetails[$parentObjectName]['ParametersTable'][$kvp.Key] = $kvp.Value
                    }
                    $DefinitionFunctionsDetails[$parentObjectName]['IsModel'] = $true
                    #Write-Host ($DefinitionFunctionsDetails | Out-String)
                }
                $context.OnComplete = $onComplete
                return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($context)
            }
        } elseif ($phase.HasParent([OpenAPI.NET.Parser.v2.PropertiesObject])) 
        {
            $objectName = $phase.Parent.Parent.DataModel.Info
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
                # In the case of x-ms-client-flatten, process the child schema objects as if they were under a higher up properties object
                $context = New-Object -TypeName OpenAPI.NET.Modeler.ModelContext
                $context.Info = $objectName
                return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($context)
            }

            $parameterName = $this.GetPascalCasedString($spec.Key)
            $ParameterDetails = @{}
            $FunctionDetails = @{
                Name = $objectName
                ParametersTable = @{}
            }
            if ($this.DefinitionFunctionsDetails.ContainsKey($FunctionDetails['Name'])) {
                $FunctionDetails = $this.DefinitionFunctionsDetails[$FunctionDetails['Name']]
            }

            if ($FunctionDetails['ParametersTable'].ContainsKey($parameterName)) {
                $ParameterDetails = $this.DefinitionFunctionsDetails[$objectName]['ParametersTable'][$parameterName]
            }
            if ($spec.Extensions.ContainsKey("x-ms-client-name")) {
                $parameterName = $this.GetPascalCasedString($spec.Extensions["x-ms-client-name"])
            }
            #Write-Host "Found parameter '$parameterName' for object '$objectName'" -BackgroundColor DarkMagenta
            $parameterType = $this.GetTypeOfSchemaObject($spec)
            $IsParamMandatory = '$false'
            if ($phase.Parent.HasParent([OpenAPI.NET.Parser.v2.SchemaObject])) {
                #Write-Host "Required: $($phase.Parent.Parent.CurrentSpecObject.Required)"
                if ($phase.Parent.Parent.CurrentSpecObject.Required -ne $null -and $phase.Parent.Parent.CurrentSpecObject.Required -contains $parameterName) {
                    $IsParamMandatory = '$true'
                }
            }
            $ValidateSetString = $null
            $ParameterDescription = $spec.Description

            if ($spec.Enum -ne $null) {
                # Process enum if x-ms-enum.ModelAsString is set to true, or there's no x-ms-enum extension
                if ((-not $spec.ContainsKey("x-ms-enum")) -or $spec.Extensions["x-ms-enum"].ModelAsString) {
                    $EnumValues = $spec.Enum | ForEach-Object {$_ -replace "'","''"}
                    $ValidateSetString = "'$($EnumValues -join "', '")'"
                }
            }
            #Write-Host "ValidateSetString: $ValidateSetString"
            $ParameterDetails['Name'] = $parameterName
            $ParameterDetails['Type'] = $parameterType
            $ParameterDetails['ValidateSet'] = $ValidateSetString
            $ParameterDetails['Mandatory'] = $IsParamMandatory
            $ParameterDetails['Description'] = $ParameterDescription

            #Write-Host "Final ParameterDetails: $($ParameterDetails | Out-String)"

            if ($parameterType) {
                #Write-Host "Add ParameterDetails to [$objectName]['ParametersTable'][$parameterName]"
                $FunctionDetails['ParametersTable'][$parameterName] = $ParameterDetails
                # The original logic has that if there's only one property, AutoRest won't generate a model - which doesn't seem to be true!
               # if ($this.GetHashtableKeyCount($FunctionDetails['ParametersTable']) -gt 1) {
                 # This is only a model if it isn't anonymous
                 if (-not $FunctioNDetails.ContainsKey('IsAnonymous') -or -not $FunctionDetails['IsAnonymous']) {
                     $FunctionDetails['IsModel'] = $true
                 }
                #}
            }

            $this.DefinitionFunctionsDetails[$FunctionDetails['Name']] = $FunctionDetails

            # Stop here so we don't process inner schema objects any further
            return [OpenAPI.NET.Modeler.ModelBuildResult]::Stop($null)
        } elseif ($phase.HasParent([OpenAPI.NET.Parser.v2.ParameterObject])) {
            # If we get here, a flattening is requested
            $parametersTable = $phase.Parent.DataModel.Info
            $parameterNextIndex = $phase.Parent.DataModel.Properties["nextIndex"]

        }
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.PropertiesObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        #Write-Host "Processing Properties for object $($this.GetName($phase.Parent.CurrentSpecObject))" -BackgroundColor DarkGreen
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.AutoRestExtensions.CodeGenerationSettings]$codeGenSettings, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        if ($codeGenSettings.ClientName)
        {
            $this.SwaggerDict['Info']['InfoName'] = $codeGenSettings.ClientName
        } else {
            $this.SwaggerDict['Info']['InfoName'] = $codeGenSettings.Name
        }

        if ($codeGenSettings.ModelsName)
        {
            $this.SwaggerDict['Info']['Models'] = $codeGenSettings.ModelsName
        } elseif ($codeGenSettings.Mname) {
            $this.SwaggerDict['Info']['Models'] = $codeGenSettings.Mname
        }

        if ($codeGenSettings.OutputDirectory)
        {
            $this.SwaggerDict['Info']['CodeOutputDirectory'] = $codeGenSettings.OutputDirectory
        } elseif ($codeGenSettings.Output) {
            $this.SwaggerDict['Info']['CodeOutputDirectory'] = $codeGenSettings.Output
        } elseif ($codeGenSettings.O) {
            $this.SwaggerDict['Info']['CodeOutputDirectory'] = $codeGenSettings.O
        }

        if ($codeGenSettings.Modeler -or $codeGenSettings.M -or $codeGenSettings.AddCredentials -or $codeGenSettings.CodeGenerator -or $codeGenSettings.G)
        {
            $this.SwaggerDict['Info']['CodeGenFileRequired'] = $true
        } else {
            $this.SwaggerDict['Info']['CodeGenFileRequired'] = $false
        }
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.PathsObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase) {
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.PathItemObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase) {
        # Let operations finish processing
        # When children are complete, apply common parameters
        $PathCommonParameters = @{}
        $index = 0
        if ($spec.Parameters -ne $null) {
            foreach ($parameter in $spec.Parameters) {
                Write-Host "Processing common parameter: $($parameter | Out-String)" -BackgroundColor DarkYellow
                $index = $this.ProcessParameter($parameter, $PathCommonParameters, $index, $null)
            }
        }
        $context = New-Object -TypeName OpenAPI.NET.Modeler.ModelContext
        $context.Info = $PathCommonParameters
        $context.Properties["nextIndex"] = $index
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($context)
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.OperationObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase) {
        # This is a single operation, like GET /path
        Write-Host "Processing operation: $($spec.OperationId)" -BackgroundColor DarkYellow
        # this -> PathItemObject -> ModelContext
        $PathCommonParameters = $phase.Parent.DataModel.Info
        $parameterNextIndex = $phase.Parent.DataModel.Properties["nextIndex"]
        $longRunningOperation = $false
        if ($spec.Extensions.ContainsKey("x-ms-long-running-operation")) {
            $longRunningOperation = $spec.Extensions["x-ms-long-running-operation"]
        }
        $x_ms_pageableObject = $null
        if ($spec.Extensions.ContainsKey("x-ms-pageable")) {
            $x_ms_pageableObject = @{}
            $ext = $spec.Extensions["x-ms-pageable"]
            if ($ext.OperationName) {
                $x_ms_pageableObject["operationName"] = $ext.OperationName
            } else {
                $x_ms_pageableObject["operationName"] = "$($spec.OperationId)Next"
            }

            $x_ms_pageableObject["itemName"] = $ext.ItemName

            if ($ext.HasPropertyDefined("nextLinkName")) {
                if ($ext.NextLinkName) {
                    $x_ms_pageableObject["nextLinkName"] = $ext.NextLinkName
                } else {
                    # When nextLinkName is explicitly defined as null, the operation is actually not pageable - just using x-ms-pageable to generate a more friendly client
                    # I don't think PSSwagger supports this second case well yet - requires more investigation
                    $x_ms_pageableObject = $null
                }
            }
        }

        $operationId = $spec.OperationId
        $FunctionDescription = ""
        if ($spec.Description) {
            $FunctionDescription = $spec.Description
        }
        $ParametersTable = @{}
        $PathCommonParameters.GetEnumerator() | ForEach-Object {
            Write-Host "Assign common parameter: $($_.Key) = $($_.Value | Out-String)" -BackgroundColor DarkYellow
            $ParametersTable[$_.Key] = $_.Value
        }

        $context = New-Object -TypeName OpenAPI.NET.Modeler.ModelContext
        $context.Info = $ParametersTable
        $context.Properties["nextIndex"] = $phase.Parent.DataModel.Properties["nextIndex"]
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($context)
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.ParameterObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase) {
        if ($phase.HasParent([OpenAPI.NET.Parser.v2.OperationObject])) {
            # phase -> OperationObject -> ModelContext
            if ($spec.Extensions.ContainsKey("x-ms-client-flatten")) {
                # Flatten the Schema object as a list of parameters instead of using this parameter
                # $context = New-Object -TypeName OpenAPI.NET.Parser.ModelContext
                # $context.Info = $ParametersTable
                # $context.Properties["nextIndex"] = $phase.Parent.DataModel.Properties["nextIndex"]
                # return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($context)
            } else {
                # Take this parameter as-is
                $phase.Parent.DataModel.Properties["nextIndex"] = $this.ProcessParameter($spec, $phase.Parent.DataModel.Info, $phase.Parent.DataModel.Properties["nextIndex"], $phase.Parent.CurrentSpecObject.OperationId)
            }
        }

        return [OpenAPI.NET.Modeler.ModelBuildResult]::Stop($null)
    }
    [int] ProcessParameter([OpenAPI.NET.Parser.v2.ParameterObject]$spec, [hashtable]$parameterTable, [int]$nextIndex, [string]$operationId) {
        Write-Host "Processing parameter: $($spec | Out-String)" -BackgroundColor DarkYellow
        $NameSpace = $this.SwaggerDict['Info'].NameSpace
        $Models = $this.SwaggerDict['Info'].Models
        $DefinitionTypeNamePrefix = "$Namespace.$Models."
        $parameterName = ''
        if ($spec.Extensions.ContainsKey("x-ms-client-name")) {
            $parameterName = $this.GetPascalCasedString($spec.Extensions["x-ms-client-name"])
        } else {
            $parameterName = $this.GetPascalCasedString($spec.Name)
        }

        $parameterType = $this.GetTypeOfParameterObject($spec)
        $AllParameterDetailsArrayTemp = @()
        $x_ms_parameter_grouping = ''
        if ($spec.Extensions.ContainsKey("x-ms-parameter-grouping")) {
            $groupObject = $spec.Extensions["x-ms-parameter-grouping"]
            $x_ms_parameter_grouping = $this.GetParameterGroupName($groupObject.Name,$operationId,$groupObject.Postfix)
        }

        $IsParamMandatory = '$false'
        $ParameterDescription = ''
        $IsParameter = $true
        # For now, we're going to assume anything with a $ref is global while anything else is local
        if ($spec.ReferenceObject -ne $null) {
            $x_ms_parameter_location = 'client'
        } else {
            $x_ms_parameter_location = 'method'
        }

        $ext = $spec.GetExtension("x-ms-parameter-location", $true)
        if ($ext) {
            $x_ms_parameter_location = $ext
        }

        if ($x_ms_parameter_location -eq "client") {
            $IsParameter = $false
        }

        if ($spec.Required) {
            $IsParamMandatory = '$true'
        }

        if ($spec.Description) {
            $ParameterDescription = $spec.Description
        }
        $ValidateSetString = ""
        if ($spec.Enum -ne $null) {
            # Process enum if x-ms-enum.ModelAsString is set to true, or there's no x-ms-enum extension
            if ((-not $spec.ContainsKey("x-ms-enum")) -or $spec.Extensions["x-ms-enum"].ModelAsString) {
                $EnumValues = $spec.Enum | ForEach-Object {$_ -replace "'","''"}
                $ValidateSetString = "'$($EnumValues -join "', '")'"
            }
        }

        $ParameterDetails = @{
            Name = $parameterName
            Type = $parameterType
            ValidateSet = $ValidateSetString
            Mandatory = $IsParamMandatory
            Description = $ParameterDescription
            IsParameter = $IsParameter
            x_ms_parameter_location = $x_ms_parameter_location
            x_ms_parameter_grouping = $x_ms_parameter_grouping
        }
        Write-Host "Adding to parameter table[$nextIndex]: $($ParameterDetails | Out-String)" -BackgroundColor DarkYellow
        $parameterTable[$nextIndex] = $ParameterDetails
        return $nextIndex+1
    }
    # TODO: Fix the bug in SpecificationObject.GetName() where the old spec.Key is being returned by the method instead of the new spec.Key
    [string] GetName([OpenAPI.NET.Parser.SpecificationObject]$spec) {
        if($spec.ReferenceObject -eq $null) { 
            return $spec.Key
        } else { 
            return $spec.ReferenceObject.Key
        }
    }
    [string] GetPascalCasedString([string]$Name)
    {
        if($Name) {
            $Name = $this.RemoveSpecialCharacter($Name)
            $startIndex = 0
            $subStringLength = 1

            return $($Name.substring($startIndex, $subStringLength)).ToUpper() + $Name.substring($subStringLength)
        }
        return $null
    }
    [string] RemoveSpecialCharacter([string]$Name)
    {
        $pattern = '[^a-zA-Z0-9]'
        return ($Name -replace $pattern, '')
    }
    [string] GetPSType([string]$specParameterType, [string]$specParameterFormat, [bool]$useSwitchType) {
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
    [string] GetTypeOfParameterObject([OpenAPI.NET.Parser.v2.ParameterObject]$spec) {
        $DefinitionTypeNamePrefix = "$($this.SwaggerDict['Info']['NameSpace']).$($this.SwaggerDict['Info']['Models'])"
        if ($spec.Type -eq $null -or $spec.Type -eq "object") {
            $typeName = "$DefinitionTypeNamePrefix.$($this.CSharpCodeNamer.GetTypeName($this.GetName($spec)))"
        } else {
            $typeName = $this.GetPSType($spec.Type,$spec.Format,$true)
        }

        # TODO: This is actually only true if the property is Required
        # If not, and x-ms-enum exists, x-ms-enum is honored
        if ($spec.Enum -ne $null -and $spec.Enum.Count -gt 1 -and $spec.Extensions.ContainsKey("x-ms-enum") -and (-not $spec.Extensions["x-ms-enum"].ModelAsString)) {
            #Write-Host "x-ms-enum enum found"
            $enumName = $this.CSharpCodeNamer.GetTypeName($spec.Extensions["x-ms-enum"].Name)
            $typeName = "$DefinitionTypeNamePrefix.$enumName"
        } elseif ($spec.Format -ne $null -and $spec.Format -as [Type]) {
            $typeName = $spec.Format
        } elseif ($spec.Type -eq "array") {
            if ($spec.Items.Type -eq $null -or $spec.Items.Type -eq "object") {
                $typeName = "$DefinitionTypeNamePrefix.$($this.CSharpCodeNamer.GetTypeName($this.GetName($spec.Items)))[]"
            } else {
                $typeName = "$($this.GetPSType($spec.Items.Type,$spec.Items.Format,$false))[]"
            }
        } elseif ($spec.Schema -ne $null) {
            # This is pretty much the only difference from GetTypeOfSchemaObject, other than the type
            # In this case, the type of the referenced schema object is the parameter type
            $typeName = $this.GetTypeOfSchemaObject($spec.Schema)
        }
        #Write-Host "Type: $typeName"
        Write-Host "ParameterType: $typeName" -BackgroundColor DarkYellow
        return $typeName
    }
    [string] GetTypeOfSchemaObject([OpenAPI.NET.Parser.v2.SchemaObject]$spec) {
        $DefinitionTypeNamePrefix = "$($this.SwaggerDict['Info']['NameSpace']).$($this.SwaggerDict['Info']['Models'])"
        if ($spec.Type -eq $null -or $spec.Type -eq "object") {
            $typeName = "$DefinitionTypeNamePrefix.$($this.CSharpCodeNamer.GetTypeName($this.GetName($spec)))"
        } else {
            $typeName = $this.GetPSType($spec.Type,$spec.Format,$true)
        }

        # TODO: This is actually only true if the property is Required
        # If not, and x-ms-enum exists, x-ms-enum is honored
        if ($spec.Enum -ne $null -and $spec.Enum.Count -gt 1 -and $spec.Extensions.ContainsKey("x-ms-enum") -and (-not $spec.Extensions["x-ms-enum"].ModelAsString)) {
            #Write-Host "x-ms-enum enum found"
            $enumName = $this.CSharpCodeNamer.GetTypeName($spec.Extensions["x-ms-enum"].Name)
            $typeName = "$DefinitionTypeNamePrefix.$enumName"
        } elseif ($spec.Format -ne $null -and $spec.Format -as [Type]) {
            $typeName = $spec.Format
        } elseif ($spec.Type -eq "array") {
            if ($spec.Items.Type -eq $null -or $spec.Items.Type -eq "object") {
                $typeName = "$DefinitionTypeNamePrefix.$($this.CSharpCodeNamer.GetTypeName($this.GetName($spec.Items)))[]"
            } else {
                $typeName = "$($this.GetPSType($spec.Items.Type,$spec.Items.Format,$false))[]"
            }
        } elseif ($spec.AdditionalProperties -ne $null -and $spec.Properties -eq $null) {
            # AutoRest generates this type of object as a Dictionary<string, T>
            # TODO: Original parsing logic does this: "System.Collections.Generic.Dictionary[[$AdditionalPropertiesType],[$AdditionalPropertiesType]]"
            # Is that right??
            #Write-Host "AP.Type: $($spec.AdditionalProperties.Type)"
                
            if ($spec.AdditionalProperties.Type -eq $null -or $spec.AdditionalProperties.Type -eq "object") {
                #Write-Host "AP.GetName: $($this.GetName($spec.AdditionalProperties))"
                $AdditionalPropertiesType = $this.CSharpCodeNamer.GetTypeName($this.GetName($spec.AdditionalProperties))
            } else {
                $AdditionalPropertiesType = $this.GetPSType($spec.AdditionalProperties.Type,$spec.AdditionalProperties.Format,$false)
            }
            $typeName = "System.Collections.Generic.Dictionary[[string],[$AdditionalPropertiesType]]"
        }
        #Write-Host "Type: $typeName"
        return $typeName
    }
    [int] GetHashtableKeyCount([PSCustomObject]$Hashtable)
    {
        $KeyCount = 0
        $Hashtable.GetEnumerator() | ForEach-Object { $KeyCount++ }    
        return $KeyCount
    }
    [string] GetParameterGroupName([string]$RawName, [string]$OperationId, [string]$Postfix) {
        if ($RawName) {
            # AutoRest only capitalizes the first letter and the first letter after a hyphen
            $newName = ''
            $capitalize = $true
            foreach ($char in $RawName.ToCharArray()) {
                if ('-' -eq $char) {
                    $capitalize = $true
                } elseif ($capitalize) {
                    $capitalize = $false
                    if ((97 -le $char) -and (122 -ge $char)) {
                        [char]$char = $char-32
                    }

                    $newName += $char
                } else {
                    $newName += $char
                }
            }

            return $this.RemoveSpecialCharacter($newName)
        } else {
            if (-not $Postfix) {
                $Postfix = "Parameters"
            }

            if ($OperationId) {
                $split = $OperationId.Split('_')
                if ($split.Count -eq 2) {
                    return "$($split[0])$($split[1])$Postfix"
                }
            }

            # Don't ask
            return "HyphenMinus$($OperationId)HyphenMinus$Postfix"
        }
    }
}