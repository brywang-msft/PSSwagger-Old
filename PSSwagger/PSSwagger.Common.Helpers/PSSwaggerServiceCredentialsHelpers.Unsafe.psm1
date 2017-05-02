function Get-BasicAuthCredentials {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [PSCredential]
        $Credential
    )

    if (-not $Credential) {
        $Credential = Get-Credential
    }

    New-Object -TypeName 'Microsoft.PowerShell.Commands.PSSwagger.BasicAuthenticationCredentialsEx' -ArgumentList $Credential.UserName,$Credential.Password
}