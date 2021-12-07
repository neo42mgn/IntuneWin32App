function Connect-MSIntuneGraph {
    <#
    .SYNOPSIS
        Get or refresh an access token using either authorization code flow or device code flow, that can be used to authenticate and authorize against resources in Graph API.

    .DESCRIPTION
        Get or refresh an access token using either authorization code flow or device code flow, that can be used to authenticate and authorize against resources in Graph API.

    .PARAMETER TenantID
        Specify the tenant name or ID, e.g. tenant.onmicrosoft.com or <GUID>.

    .PARAMETER ClientID
        Application ID (Client ID) for an Azure AD service principal. Uses by default the 'Microsoft Intune PowerShell' service principal Application ID.

    .PARAMETER RedirectUri
        Specify the Redirect URI (also known as Reply URL) of the custom Azure AD service principal.

    .PARAMETER DeviceCode
        Specify delegated login using devicecode flow, you will be prompted to navigate to https://microsoft.com/devicelogin

    .PARAMETER Interactive
        Specify to force an interactive prompt for credentials.

    .PARAMETER Refresh
        Specify to refresh an existing access token.

    .NOTES
        Author:      Nickolaj Andersen
        Contact:     @NickolajA
        Created:     2021-08-31
        Updated:     2021-08-31

        Version history:
        1.0.0 - (2021-08-31) Script created
    #>
    [CmdletBinding(DefaultParameterSetName = "Interactive")]
    param(
        [parameter(Mandatory = $true, ParameterSetName = "Interactive", HelpMessage = "Specify the tenant name or ID, e.g. tenant.onmicrosoft.com or <GUID>.")]
        [parameter(Mandatory = $true, ParameterSetName = "DeviceCode")]
        [parameter(Mandatory = $true, ParameterSetName = "Certificate")]
        [ValidateNotNullOrEmpty()]
        [string]$TenantID,
        
        [parameter(Mandatory = $false, ParameterSetName = "Interactive", HelpMessage = "Application ID (Client ID) for an Azure AD service principal. Uses by default the 'Microsoft Intune PowerShell' service principal Application ID.")]
        [parameter(Mandatory = $false, ParameterSetName = "DeviceCode")]
        [parameter(Mandatory = $false, ParameterSetName = "Certificate")]
        [ValidateNotNullOrEmpty()]
        [string]$ClientID = "d1ddf0e4-d672-4dae-b554-9d5bdfd93547",

        [parameter(Mandatory = $false, ParameterSetName = "Interactive", HelpMessage = "Specify the Redirect URI (also known as Reply URL) of the custom Azure AD service principal.")]
        [parameter(Mandatory = $false, ParameterSetName = "DeviceCode")]
        [parameter(Mandatory = $false, ParameterSetName = "Certificate")]
        [ValidateNotNullOrEmpty()]
        [string]$RedirectUri = [string]::Empty,

        [parameter(Mandatory = $false, ParameterSetName = "Interactive", HelpMessage = "Specify to force an interactive prompt for credentials.")]
        [switch]$Interactive,

        [parameter(Mandatory = $true, ParameterSetName = "DeviceCode", HelpMessage = "Specify to do delegated login using devicecode flow, you will be prompted to navigate to https://microsoft.com/devicelogin")]
        [switch]$DeviceCode,

        [parameter(Mandatory = $false, ParameterSetName = "Interactive", HelpMessage = "Specify to refresh an existing access token.")]
        [parameter(Mandatory = $false, ParameterSetName = "DeviceCode")]
        [parameter(Mandatory = $false, ParameterSetName = "Certificate")]
        [switch]$Refresh,

        [parameter(Mandatory = $false, ParameterSetName = "Certificate", HelpMessage = "Specify to use a certificate for authentication.")]
        [string]$CertThumbprint
    )
    Begin {
        # Determine the correct RedirectUri (also known as Reply URL) to use with MSAL.PS
        if ($ClientID -like "d1ddf0e4-d672-4dae-b554-9d5bdfd93547") {
            $RedirectUri = "urn:ietf:wg:oauth:2.0:oob"
        }
        else {
            if (-not([string]::IsNullOrEmpty($ClientID))) {
                Write-Verbose -Message "Using custom Azure AD service principal specified with Application ID: $($ClientID)"

                # Adjust RedirectUri parameter input in case non was passed on command line
                if ([string]::IsNullOrEmpty($RedirectUri)) {
                    switch -Wildcard ($PSVersionTable["PSVersion"]) {
                        "5.*" {
                            $RedirectUri = "https://login.microsoftonline.com/common/oauth2/nativeclient"
                        }
                        "7.*" {
                            $RedirectUri = "http://localhost"
                        }
                    }
                }
            }
        }
        Write-Verbose -Message "Using RedirectUri with value: $($RedirectUri)"

        # Set default error action preference configuration
        $ErrorActionPreference = "Stop"
    }
    Process {
        Write-Verbose -Message "Using authentication flow: $($PSCmdlet.ParameterSetName)"

        try {
            # Construct table with common parameter input for Get-MsalToken cmdlet
            $AccessTokenArguments = @{
                "TenantId" = $TenantID
                "ClientId" = $ClientID
                "RedirectUri" = $RedirectUri
                "ErrorAction" = "Stop"
            }

            # Dynamically add parameter input for Get-MsalToken based on parameter set name
            switch ($PSCmdlet.ParameterSetName) {
                "Interactive" {
                    if ($PSBoundParameters["Refresh"]) {
                        $AccessTokenArguments.Add("ForceRefresh", $true)
                        $AccessTokenArguments.Add("Silent", $true)
                    }
                }
                "DeviceCode" {
                    if ($PSBoundParameters["Refresh"]) {
                        $AccessTokenArguments.Add("ForceRefresh", $true)
                    }
                }
                "Certificate" {
                    if ($PSBoundParameters["Refresh"]) {
                        $AccessTokenArguments["ClientCertificate"] = Get-Item -Path "Cert:\CurrentUser\My\$CertThumbprint"
                    }
                }
            }

            # Dynamically add parameter input for Get-MsalToken based on command line input
            if ($PSBoundParameters["Interactive"]) {
                $AccessTokenArguments.Add("Interactive", $true)
            }
            if ($PSBoundParameters["DeviceCode"]) {
                if (-not($PSBoundParameters["Refresh"])){
                    $AccessTokenArguments.Add("DeviceCode", $true)
                }
            }
            if ($PSBoundParameters["Certificate"]){
                    $AccessTokenArguments["ClientCertificate"] = Get-Item -Path "Cert:\CurrentUser\My\$CertThumbprint"
            }

            try {
                # Attempt to retrieve or refresh an access token
                $Global:AccessToken = Get-MsalToken @AccessTokenArguments
                Write-Verbose -Message "Successfully retrieved access token"
                
                try {
                    # Construct the required authentication header
                    $Global:AuthenticationHeader = New-AuthenticationHeader -AccessToken $Global:AccessToken
                    Write-Verbose -Message "Successfully constructed authentication header"

                    # Handle return value
                    return $Global:AuthenticationHeader
                }
                catch [System.Exception] {
                    Write-Warning -Message "An error occurred while attempting to construct authentication header. Error message: $($PSItem.Exception.Message)"
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "An error occurred while attempting to retrieve or refresh access token. Error message: $($PSItem.Exception.Message)"
            }
        }
        catch [System.Exception] {
            Write-Warning -Message "An error occurred while constructing parameter input for access token retrieval. Error message: $($PSItem.Exception.Message)"
        }
    }
}