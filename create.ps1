#################################################
# HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE-Create
# PowerShell V2
#################################################

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

function ConvertTo-HelloIDAccountObject {
    [CmdletBinding()]
    param (
        $TargetAccountObject
    )

    $helloIDAccountObject = [PSCustomObject]@{
        firstname            = $TargetAccountObject.firstname
        lastname             = $TargetAccountObject.lastname
        hda_personnelnumber  = $TargetAccountObject.hda_personnelnumber
        internalemailaddress = $TargetAccountObject.internalemailaddress
        isdisabled           = $TargetAccountObject.isdisabled
        domainname           = $TargetAccountObject.domainname
        address1_telephone1  = $TargetAccountObject.address1_telephone1
        parentsystemuserid   = $TargetAccountObject._parentsystemuserid_value
        businessunitid       = $TargetAccountObject._businessunitid_value
    }

    if ($outputContext.Data.PSObject.Properties.Name -contains 'id') {
        $helloIDAccountObject | Add-Member -Name 'id' -Value $TargetAccountObject.systemuserid -MemberType NoteProperty
    }

    Write-Output $helloIDAccountObject
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

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

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.AccountField
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [accountFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]
        Write-Information "Verifying if a Microsoft-Dynamics365-CE account exists where $correlationField is: [$correlationValue]"

        $splatGetUserParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/data/v9.2/systemusers?`$filter=$($correlationField) eq '$($correlationValue)'"
            Method  = 'GET'
            Headers = $headers
        }
    
        $correlatedAccount = (Invoke-RestMethod @splatGetUserParams).value
    }

    if ($correlatedAccount.Count -eq 0) {
        $lifecycleProcess = 'CreateAccount'
    }
    elseif ($correlatedAccount.Count -eq 1) {
        $lifecycleProcess = 'CorrelateAccount'
        $correlatedAccount = $correlatedAccount | select-object -first 1
    }
    elseif ($correlatedAccount.Count -gt 1) {
        throw "Multiple accounts found for person where $correlationField is: [$correlationValue]"
    }

    # Manager Lookup
    if (-not [string]::IsNullOrEmpty($actionContext.References.ManagerAccount)) {
        $filterField = 'systemuserid'
        $filterValue = $actionContext.References.ManagerAccount
        $managerDescription = "manager reference [$($actionContext.References.ManagerAccount)]"
    }
    elseif (-not [string]::IsNullOrEmpty($actionContext.Data.parentsystemuserid)) {
        $filterField = 'hda_personnelnumber'
        $filterValue = $actionContext.Data.parentsystemuserid
        $managerDescription = "hda_personnelnumber [$($actionContext.Data.parentsystemuserid)]"
    }
    else {
        Write-Information 'No manager configured, skipping manager lookup'
    }
            
    if (-not [string]::IsNullOrEmpty($filterField) -and -not [string]::IsNullOrEmpty($filterValue)) {
        Write-Information "Verifying if the Microsoft-Dynamics365-CE manager account exists for $managerDescription"
            
        $splatGetUserParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/api/data/v9.2/systemusers?`$filter=$filterField eq '$filterValue'"
            Method  = 'GET'
            Headers = $headers
        }
        $correlatedManagerAccount = (Invoke-RestMethod @splatGetUserParams).value | Select-Object -First 1

        if ($null -eq $correlatedManagerAccount) {
            throw "Could not find the manager with $managerDescription for account with hda_personnelnumber [$($actionContext.Data.hda_personnelnumber)]"
        }
        Write-Information "Found the manager with $managerDescription for account with hda_personnelnumber [$($actionContext.Data.hda_personnelnumber)]"
        $actionContext.Data.parentsystemuserid = $correlatedManagerAccount.systemuserid
    }

    # Change the parentsystemuserid and businessunitid to the correct format for Microsoft-Dynamics365-CE
    if (-not([string]::IsNullOrEmpty($actionContext.Data.parentsystemuserid))) {
        $actionContext.Data | Add-Member -Name 'parentsystemuserid@odata.bind' -Value "/systemusers($($actionContext.Data.parentsystemuserid))" -MemberType NoteProperty
        $actionContext.Data.PSObject.Properties.Remove('parentsystemuserid')
    }
    if (-not([string]::IsNullOrEmpty($actionContext.Data.businessunitID))) {
        $actionContext.Data | Add-Member -Name 'businessunitid@odata.bind' -Value "/businessunits($($actionContext.Data.businessunitID))" -MemberType NoteProperty
        $actionContext.Data.PSObject.Properties.Remove('businessunitid')
    }            

    # Process
    switch ($lifecycleProcess) {
        'CreateAccount' {
            $splatCreateParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/data/v9.2/systemusers"
                Method  = 'POST'
                Body    = $actionContext.Data | ConvertTo-Json
                Headers = $headers
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating Microsoft-Dynamics365-CE account'
               
                $null = Invoke-RestMethod @splatCreateParams

                # Extra step to retrieve the created account, since the POST request does not return the created object
                $splatGetCreatedUserParams = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/api/data/v9.2/systemusers?`$filter=hda_personnelnumber eq '$($actionContext.Data.hda_personnelnumber)'"
                    Method  = 'GET'
                    Headers = $headers
                }
                $createdAccount = (Invoke-RestMethod @splatGetCreatedUserParams).value | select-object -first 1

                $outputContext.Data = ConvertTo-HelloIDAccountObject $createdAccount
                $outputContext.AccountReference = $createdAccount.systemuserid
            }
            else {
                Write-Information '[DryRun] Create and correlate Microsoft-Dynamics365-CE account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating Microsoft-Dynamics365-CE account'

            $outputContext.Data = ConvertTo-HelloIDAccountObject $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.systemuserid
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $lifecycleProcess
            Message = $auditLogMessage
            IsError = $false
        })
}
catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Microsoft-Dynamics365-CEError -ErrorObject $ex
        $auditLogMessage = "Could not create or correlate Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not create or correlate Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}