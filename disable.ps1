##################################################
# HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE-Disable
# PowerShell V2
##################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

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
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

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

    Write-Information 'Verifying if a Microsoft-Dynamics365-CE account exists'
    $splatGetUserParams = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/api/data/v9.2/systemusers?`$filter=systemuserid eq '$($actionContext.References.Account)'"
        Method  = 'GET'
        Headers = $headers
    }
    $correlatedAccount = (Invoke-RestMethod @splatGetUserParams).value | select-object -first 1

    if ($null -ne $correlatedAccount) {
        $lifecycleProcess = 'DisableAccount'
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'DisableAccount' {

            $splatDisableParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/data/v9.2/systemusers($($actionContext.References.Account))"
                Method  = 'PATCH'
                Body    = (@{
                    isdisabled = $true
                } | ConvertTo-Json)
                Headers = $headers
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Disabling Microsoft-Dynamics365-CE account with accountReference: [$($actionContext.References.Account)]"

                $null = Invoke-RestMethod @splatDisableParams
            }
            else {
                Write-Information "[DryRun] Disable Microsoft-Dynamics365-CE account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Disable account: [$($actionContext.References.Account)] was successful. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }
    }
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Microsoft-Dynamics365-CEError -ErrorObject $ex
        $auditLogMessage = "Could not disable Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not disable Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)]. Error: $($_.Exception.Message). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}