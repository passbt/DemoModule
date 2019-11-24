[CmdletBinding()]
param ( )

$ErrorActionPreference = 'Stop'; # stop on all errors

function Update-Directory
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string] $Source,

		[Parameter(Mandatory = $true)]
		[string] $Destination
	)

	$Source = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Source)
	$Destination = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Destination)

	if (-not (Test-Path -LiteralPath $Destination))
	{
		$null = New-Item -Path $Destination -ItemType Directory -ErrorAction Stop
	}

	try
	{
		$sourceItem = Get-Item -LiteralPath $Source -ErrorAction Stop
		$destItem = Get-Item -LiteralPath $Destination -ErrorAction Stop

		if ($sourceItem -isnot [System.IO.DirectoryInfo] -or $destItem -isnot [System.IO.DirectoryInfo])
		{
			throw 'Not Directory Info'
		}
	}
	catch
	{
		throw 'Both Source and Destination must be directory paths.'
	}

    #Clean up Old modules. Old modules are any directory with a name formated like 1.0.0 and doesn't match the destination name.
    Write-Host "Searching for old modules in $($destItem.PSParentPath)\*" -Verbose

    $oldModules = @()
    $oldModules = Get-ChildItem -path "$($destItem.PSParentPath)\*" | where {$_.PSIsContainer -and $_.name -match '\d{1,3}\.\d{1,3}\.\d{1,3}' -and $_.name -ne $destItem.name}
    
    foreach ($oldModule in $oldModules)
    {
        Remove-item -Path $oldModule -Recurse -Force
    }
    
	$sourceFiles = Get-ChildItem -Path $Source -Recurse |
				   Where-Object { -not $_.PSIsContainer }

	foreach ($sourceFile in $sourceFiles)
	{
		$relativePath = Get-RelativePath $sourceFile.FullName -RelativeTo $Source
		$targetPath = Join-Path $Destination $relativePath

        Write-Verbose "Right before Get-FileHash"

        if ($sourceFile.FullName -notmatch '\.chocolateyPending' -and $sourceFile.FullName -notmatch '\.nupkg' -and $sourceFile.FullName -notmatch '\.nuspec'  )
        {
		    $sourceHash = Get-FileHash -Path $sourceFile.FullName
		    $destHash = Get-FileHash -Path $targetPath
            Write-Verbose "Out of Get-FileHash"

		    if ($sourceHash -ne $destHash)
		    {
			    $targetParent = Split-Path $targetPath -Parent

			    if (-not (Test-Path -Path $targetParent -PathType Container))
			    {
				    $null = New-Item -Path $targetParent -ItemType Directory -ErrorAction Stop
			    }

			    Write-Verbose "Updating file $relativePath to new version."
			    Copy-Item $sourceFile.FullName -Destination $targetPath -Force -ErrorAction Stop
		    }
        }
        else
        {
            Write-Verbose "Skipping $($sourceFile.FullName)."
        }
	}

	$targetFiles = Get-ChildItem -Path $Destination -Recurse |
				   Where-Object { -not $_.PSIsContainer }

	foreach ($targetFile in $targetFiles)
	{
		$relativePath = Get-RelativePath $targetFile.FullName -RelativeTo $Destination
		$sourcePath = Join-Path $Source $relativePath

		if (-not (Test-Path $sourcePath -PathType Leaf))
		{
			Write-Verbose "Removing unknown file $relativePath from module folder."
			Remove-Item -LiteralPath $targetFile.FullName -Force -ErrorAction Stop
		}
	}

}

function Get-RelativePath
{
	param ( [string] $Path, [string] $RelativeTo )
	return $Path -replace "^$([regex]::Escape($RelativeTo))\\?"
}

function Get-FileHash
{
	param ([string] $Path)

	if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
	{
		return $null
	}

	$item = Get-Item -LiteralPath $Path
	if ($item -isnot [System.IO.FileSystemInfo])
	{
		return $null
	}

	$stream = $null

	try
	{
		$sha = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
		$stream = $item.OpenRead()
		$bytes = $sha.ComputeHash($stream)
		return [convert]::ToBase64String($bytes)
	}
	finally
	{
		if ($null -ne $stream) { $stream.Close() }
		if ($null -ne $sha)    { $sha.Clear() }
	}
}

$sourceDirectory      = Split-Path $PSScriptRoot -Parent
Write-Verbose " PSD File: $sourceDirectory\*.psd1"
$manifestFile    = (Get-ChildItem -Path $sourceDirectory\*.psd1 | Select-Object -First 1).FullName
$manifest        = Test-ModuleManifest -Path $manifestFile -WarningAction Ignore -ErrorAction Stop

$modulePath      = Join-Path $env:ProgramFiles WindowsPowerShell\Modules
$targetDirectory = Join-Path $modulePath $manifest.Name

if ($PSVersionTable.PSVersion.Major -ge 5)
{
	$targetDirectory = Join-Path $targetDirectory $manifest.Version.ToString()
}

Update-Directory -Source $sourceDirectory -Destination $targetDirectory

if ($PSVersionTable.PSVersion.Major -lt 4)
{
	$modulePaths = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split ';'
	if ($modulePaths -notcontains $modulePath)
	{
		Write-Verbose "Adding '$modulePath' to PSModulePath."

		$modulePaths = @(
			$modulePath
			$modulePaths
		)

		$newModulePath = $modulePaths -join ';'

		[Environment]::SetEnvironmentVariable('PSModulePath', $newModulePath, 'Machine')
		$env:PSModulePath += ";$modulePath"
	}
}