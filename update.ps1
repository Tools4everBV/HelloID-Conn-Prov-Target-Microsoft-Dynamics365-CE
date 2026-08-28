#################################################
# HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE-Update
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
            
            # Extra population of the outputContext to prevent auditlogs when there are no changes.
            $outputContext.Data.parentsystemuserid = $correlatedManagerAccount.systemuserid
        }

        $correlatedAccount = ConvertTo-HelloIDAccountObject $correlatedAccount
        $outputContext.PreviousData = $correlatedAccount 

        # Always compare the account against the current account in target system
        $splatCompareProperties = @{
            ReferenceObject  = @($correlatedAccount.PSObject.Properties)
            DifferenceObject = @($actionContext.Data.PSObject.Properties)
        }
        $propertiesChanged = Compare-Object @splatCompareProperties -PassThru | Where-Object { $_.SideIndicator -eq '=>' }
        if ($propertiesChanged) {
            $lifecycleProcess = 'UpdateAccount'
        }
        else {
            $lifecycleProcess = 'NoChanges'
        }
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'UpdateAccount' {
            Write-Information "Account property(s) required to update: $($propertiesChanged.Name -join ', ')"

            $body = @{}
            foreach ($property in $propertiesChanged.Name) {
                $body[$property] = $actionContext.Data.$property
            }

            # Change the parentsystemuserid and businessunitid to the correct format for Microsoft-Dynamics365-CE
            if (-not([string]::IsNullOrEmpty($body.parentsystemuserid))) {
                $body['parentsystemuserid@odata.bind'] = "/systemusers($($actionContext.Data.parentsystemuserid))"
                $body.Remove('parentsystemuserid')
            }
            if (-not([string]::IsNullOrEmpty($body.businessunitID))) {
                $body['businessunitid@odata.bind'] = "/businessunits($($body['businessunitid']))"
                $body.Remove('businessunitid')
            }  

            $splatUpdateParams = @{
                Uri     = "$($actionContext.Configuration.BaseUrl)/api/data/v9.2/systemusers($($actionContext.References.Account))"
                Method  = 'PATCH'
                Body    = ($body | ConvertTo-Json)
                Headers = $headers
            }

            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Updating Microsoft-Dynamics365-CE account with accountReference: [$($actionContext.References.Account)]"
                
                $null = Invoke-RestMethod @splatUpdateParams
            }
            else {
                Write-Information "[DryRun] Update Microsoft-Dynamics365-CE account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Update account was successful, Account property(s) updated: [$($propertiesChanged.name -join ',')]"
                    IsError = $false
                })
            break
        }

        'NoChanges' {
            Write-Information "No changes to Microsoft-Dynamics365-CE account with accountReference: [$($actionContext.References.Account)]"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Skipped updating Microsoft-Dynamics365-CE account with AccountReference: [$($actionContext.References.Account)]. Reason: No changes."
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $false
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
                    IsError = $true
                })
            break
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Microsoft-Dynamics365-CEError -ErrorObject $ex
        $auditLogMessage = "Could not update Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not update Microsoft-Dynamics365-CE account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
}
