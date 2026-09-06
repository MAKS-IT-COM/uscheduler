#requires -Version 7.0
#requires -PSEdition Core

function Get-NpmRootPackageJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot
    )

    $packageJsonPath = Join-Path $WorkspaceRoot 'package.json'
    if (-not (Test-Path $packageJsonPath -PathType Leaf)) {
        throw "package.json not found at '$packageJsonPath'."
    }

    return Get-Content -Path $packageJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-NpmWorkspacesConfigured {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot
    )

    $json = Get-NpmRootPackageJson -WorkspaceRoot $WorkspaceRoot
    if (-not $json.PSObject.Properties['workspaces'] -or $null -eq $json.workspaces) {
        return $false
    }

    $workspaces = $json.workspaces
    if ($workspaces -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($workspaces)
    }

    if ($workspaces -is [System.Collections.IEnumerable]) {
        $entries = @($workspaces | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        return $entries.Count -gt 0
    }

    return $false
}

function Assert-NpmRootPackageName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPackageName
    )

    $json = Get-NpmRootPackageJson -WorkspaceRoot $WorkspaceRoot
    $rootPackageName = [string]$json.name
    if ([string]::IsNullOrWhiteSpace($rootPackageName)) {
        throw "Root package.json at '$WorkspaceRoot' is missing 'name'."
    }

    if ($rootPackageName -ne $ExpectedPackageName) {
        throw "publishOrder package '$ExpectedPackageName' does not match root package name '$rootPackageName' (npm workspaces not configured)."
    }
}

Export-ModuleMember -Function Test-NpmWorkspacesConfigured, Assert-NpmRootPackageName, Get-NpmRootPackageJson
