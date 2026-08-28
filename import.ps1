#################################################
# HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE-Import
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
    Write-Information 'Starting Microsoft-Dynamics365-CE account entitlement import'

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
    $uri = "$($actionContext.Configuration.BaseUrl)/api/data/v9.2/systemusers"

    do {
        $splatImportAccountParams = @{
            Uri     = $uri
            Method  = 'GET'
            Headers = $headers
        }
        $response = Invoke-RestMethod @splatImportAccountParams
        if ($response.value.Count -gt 0) {
            foreach ($importedAccount in $response.value) {
                $importedAccount = ConvertTo-HelloIDAccountObject $importedAccount
                $data = $importedAccount | Select-Object -Property $actionContext.ImportFields

                # Make sure the displayName has a value
                $displayName = "$($importedAccount.firstName) $($importedAccount.lastName)".trim()
                if ([string]::IsNullOrEmpty($displayName)) {
                    $displayName = $importedAccount.Id
                }

                # Make sure the userName has a value
                $username = "$($importedAccount.domainname)"
                if ([string]::IsNullOrWhiteSpace($importedAccount.domainname)) {
                    $username = "$($importedAccount.Id)"
                }

                # Set Enabled based on importedAccount status
                $isEnabled = $false
                if ($importedAccount.isdisabled -eq $false) {
                    $isEnabled = $true
                }

                Write-Output @{
                    AccountReference = $importedAccount.Id
                    DisplayName      = $displayName
                    UserName         = $username
                    Enabled          = $isEnabled
                    Data             = $data
                }
            }
        }
        $uri = $response.'@odata.nextLink'
    } while ($null -ne $uri)

    Write-Information 'Microsoft-Dynamics365-CE account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-Microsoft-Dynamics365-CEError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import Microsoft-Dynamics365-CE account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import Microsoft-Dynamics365-CE account entitlements. Error: $($ex.Exception.Message)"
    }
}
