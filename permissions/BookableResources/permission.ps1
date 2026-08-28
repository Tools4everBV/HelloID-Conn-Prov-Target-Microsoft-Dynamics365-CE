################################################################
# HelloID-Conn-Prov-Target-Microsoft-Dynamics365-CE-GrantPermission-BookableResources
# PowerShell V2
################################################################

try {
    $permissions = @(
        @{
            DisplayName = 'Bookable Resource'
            Reference   = 'BookableResource'
        }
    )

    foreach ($permission in $permissions) {
        $outputContext.Permissions.Add(
            @{
                DisplayName    = $permission.DisplayName
                Identification = @{
                    Reference = $permission.Reference
                }
            }
        )
    }
} catch {
    Write-Warning "Error at Line '$($_.InvocationInfo.ScriptLineNumber)': $($_.InvocationInfo.Line). Error: $($_.Exception.Message)"
}