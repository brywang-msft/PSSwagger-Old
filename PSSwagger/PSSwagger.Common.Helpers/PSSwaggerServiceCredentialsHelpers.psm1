function Get-PSBasicAuthCredentialsInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [PSCredential]
        $Credential
    )

    if (-not $Credential) {
        $Credential = Get-Credential
    }

    $typeName = ''
    $argList = $null
    if(('Microsoft.PowerShell.Commands.PSSwagger.PSBasicAuthenticationEx' -as [Type]))
    {
        # If the Extended type exists, use it
        $typeName = 'Microsoft.PowerShell.Commands.PSSwagger.PSBasicAuthenticationEx'
        $argList = $Credential.UserName,$Credential.Password
    } else {
        # Otherwise this version should exist
        $typeName = 'Microsoft.PowerShell.Commands.PSSwagger.PSBasicAuthentication'
        $argList = $Credential.UserName,$Credential.Password
    }

    New-Object -TypeName $typeName -ArgumentList $argList
}

function Get-PSApiKeyCredentialsInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]
        $APIKey,

        [Parameter(Mandatory=$false)]
        [string]
        $In,

        [Parameter(Mandatory=$false)]
        [string]
        $Name
    )

    New-Object -TypeName 'Microsoft.PowerShell.Commands.PSSwagger.PSApiKeyAuthentication' -ArgumentList $APIKey,$In,$Name
}

function Get-PSEmptyAuthCredentialsInternal {
    [CmdletBinding()]
    param()

    New-Object -TypeName 'Microsoft.PowerShell.Commands.PSSwagger.PSDummyAuthentication'
}