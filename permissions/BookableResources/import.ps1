####################################################################
# HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE-ImportPermissions-BookableResources
# PowerShell V2
####################################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Configure, must be the same as the values used in retrieve permissions
$permissionReference = 'BookableResource'
$permissionDisplayName = 'Bookable Resource'

#region functions
function Resolve-Microsoft-Dynamics365-CEError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            if ($errorDetailsObject.error.message) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error.message
            }
            elseif ($errorDetailsObject.error_description) {
                $httpErrorObj.FriendlyMessage = $errorDetailsObject.error_description
            }
            else {
                $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails 
            }
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
            Write-Warning $_.Exception.Message
        }

        if ($httpErrorObj.FriendlyMessage.Length -gt 500) {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.FriendlyMessage.Substring(0, 500) + "..."
        }

        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Information 'Starting Microsoft-Dynamics365-CE permission entitlement import'

    $splatTokenParams = @{
        Uri     = "https://login.microsoftonline.com/$($actionContext.Configuration.tenant_id)/oauth2/token"
        Method  = 'POST'
        Body    = @{
            grant_type    = 'client_credentials'
            client_id     = $actionContext.Configuration.client_id
            client_secret = $actionContext.Configuration.client_secret
            resource      = $actionContext.Configuration.BaseUrl
            tenant_id     = $actionContext.Configuration.tenant_id
        }
        Headers = @{
            'Content-Type' = 'application/x-www-form-urlencoded'
        }
    }
    $accessToken = (Invoke-RestMethod @splatTokenParams).access_token

    $headers = @{
        Authorization  = "Bearer $accessToken"
        'Content-Type' = 'application/json'
    }

    $maxPageSize = 100
    $headers.add('Prefer', "odata.maxpagesize=$maxPageSize")
    $uri = "$($actionContext.Configuration.BaseUrl)/api/data/v9.2/bookableresources"

    do {
        $splatGetBookableResourcesParams = @{
            Uri     = $uri
            Method  = 'GET'
            Headers = $headers
        }
        $response = Invoke-RestMethod @splatGetBookableResourcesParams
        if ($response.value.Count -gt 0) {
            $permission = @{
                PermissionReference = @{
                    Reference = $permissionReference
                }
                Description         = "$($permissionDisplayName)"
                DisplayName         = "$($permissionDisplayName)"
                AccountReferences   = @(($response.value._userid_value | where-object {$_ -ne $null}))
            }

            if ($permission.AccountReferences.count -gt 0) {
                Write-Output $permission
            }
        }
        $uri = $response.'@odata.nextLink'
    } while ($null -ne $uri)

    Write-Information 'Microsoft-Dynamics365-CE permission entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Microsoft-Dynamics365-CEError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Microsoft-Dynamics365-CE permission entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Microsoft-Dynamics365-CE permission entitlements. Error: $($ex.Exception.Message)"
    }
}