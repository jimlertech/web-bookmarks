#requires -Version 7.5
[CmdletBinding()]
param(
    [string]$Commit = 'HEAD',
    [switch]$VerifyOnly,
    [string]$RecordDirectory = '\\jimbrownhome1.local\c$\ProgramData\SolutionDeploy\apps\solution-deploy\data\releases'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$script:GitHubRepository = 'jimlertech/web-bookmarks'
$script:ReleaseTagPrefix = 'tampermonkey-v'
$script:BundleName = 'webbookmarks-palette.user.js'

function Invoke-UserscriptTool {
    param([string]$Name, [string[]]$Arguments, [string]$Repository, [switch]$Capture)
    $tool = (Get-Command $Name -CommandType Application | Select-Object -First 1).Source
    Invoke-DeploymentCommand $tool $Arguments $Repository -Capture:$Capture
}

function Get-UserscriptReleases {
    param([string]$Repository)
    $json = Invoke-UserscriptTool gh @('release', 'list', '--repo', $script:GitHubRepository,
        '--limit', '100', '--json', 'tagName,publishedAt') $Repository -Capture
    @($json | ConvertFrom-Json -AsHashtable -DateKind String)
}

function Get-UserscriptReleaseDetails {
    param([string]$Repository, [string]$Tag)
    $json = Invoke-UserscriptTool gh @('release', 'view', $Tag, '--repo', $script:GitHubRepository,
        '--json', 'tagName,publishedAt') $Repository -Capture
    $json | ConvertFrom-Json -AsHashtable -DateKind String
}

function Get-UserscriptLatestTag {
    param([string]$Repository)
    ([string](Invoke-UserscriptTool gh @('api', "repos/$script:GitHubRepository/releases/latest", '--jq', '.tag_name') $Repository -Capture)).Trim()
}

function Get-UserscriptRaw {
    param([string]$Tag)
    $uri = "https://github.com/$script:GitHubRepository/releases/download/$Tag/$script:BundleName"
    (Invoke-WebRequest -Uri $uri -TimeoutSec 30).Content
}

function Get-UserscriptLatestRaw {
    $uri = "https://github.com/$script:GitHubRepository/releases/latest/download/$script:BundleName"
    (Invoke-WebRequest -Uri $uri -TimeoutSec 30).Content
}

function Get-UserscriptVersion {
    param([string]$Content)
    if ($Content -notmatch '(?m)^// @version\s+(\d+\.\d+\.\d+)\s*$') {
        throw 'Userscript metadata must contain a numeric three-part @version.'
    }
    [version]$Matches[1]
}

function Invoke-UserscriptRelease {
    param([string]$Repository, [string]$Commit, [switch]$VerifyOnly, [string]$RecordDirectory)
    $sourceCommit = Resolve-CommonReleaseSource $Repository $Commit
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('web-bookmarks-release-' + [guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($temporary) | Out-Null
    try {
        $archivePath = Join-Path $temporary 'userscript.zip'
        Invoke-UserscriptTool git @('archive', '--format=zip', "--output=$archivePath", $sourceCommit,
            "tampermonkey/$script:BundleName", 'tampermonkey/src/header.txt') $Repository
        Expand-Archive -LiteralPath $archivePath -DestinationPath $temporary
        $bundlePath = Join-Path $temporary "tampermonkey\$script:BundleName"
        $headerPath = Join-Path $temporary 'tampermonkey\src\header.txt'
        $bundle = [IO.File]::ReadAllText($bundlePath).Replace("`r`n", "`n")
        $header = [IO.File]::ReadAllText($headerPath).Replace("`r`n", "`n").TrimEnd()
        if (-not $bundle.StartsWith($header + "`n")) { throw 'Committed bundle metadata differs from src/header.txt. Rebuild and commit first.' }
        $version = Get-UserscriptVersion $bundle
        $releases = @(Get-UserscriptReleases $Repository)
        $current = $null
        $currentVersion = $null
        if ($releases.Count) {
            $current = $releases | Where-Object { $_.tagName -match "^$([regex]::Escape($script:ReleaseTagPrefix))\d+\.\d+\.\d+$" } |
                Sort-Object { [version]($_.tagName -replace "^$([regex]::Escape($script:ReleaseTagPrefix))", '') } -Descending |
                Select-Object -First 1
            if (-not $current) { throw 'GitHub Releases contains no Tampermonkey release tag.' }
            $currentVersion = [version]($current.tagName -replace "^$([regex]::Escape($script:ReleaseTagPrefix))", '')
        }

        $releaseTag = "$script:ReleaseTagPrefix$version"
        $published = ''
        if ($current) {
            $published = (Get-UserscriptRaw $current.tagName).Replace("`r`n", "`n")
        }
        if ($published -cne $bundle) {
            if ($VerifyOnly) { throw 'Latest GitHub Release differs from the committed bundle. Nothing was recorded.' }
            if ($currentVersion -and $version -le $currentVersion) {
                throw 'Increase @version before publishing changed userscript content.'
            }
            Invoke-UserscriptTool gh @('release', 'create', $releaseTag, $bundlePath,
                '--repo', $script:GitHubRepository, '--title', "Tampermonkey $version",
                '--notes', 'WebBookmarks command palette userscript.', '--target', $sourceCommit, '--latest') $Repository
        }

        $release = Get-UserscriptReleaseDetails $Repository $releaseTag
        $latestTag = Get-UserscriptLatestTag $Repository
        if ($release.tagName -cne $releaseTag -or $latestTag -cne $releaseTag) {
            throw 'The published Tampermonkey Release is not the latest GitHub Release.'
        }
        $published = (Get-UserscriptRaw $releaseTag).Replace("`r`n", "`n")
        if ($published -cne $bundle) { throw 'GitHub Release asset did not verify against the committed bundle. Nothing was recorded.' }
        $latest = (Get-UserscriptLatestRaw).Replace("`r`n", "`n")
        if ($latest -cne $bundle) { throw 'Latest GitHub Release URL did not verify against the committed bundle. Nothing was recorded.' }
        $completed = [DateTimeOffset]::Parse([string]$release.publishedAt).ToLocalTime().ToString('o')
        $record = @{
            app = 'web-bookmarks'
            component = 'tampermonkey'
            sourceCommit = $sourceCommit
            completedLocal = $completed
            version = $version.ToString()
            releaseTag = $releaseTag
        }
        [IO.Directory]::CreateDirectory($RecordDirectory) | Out-Null
        $recordPath = Join-Path $RecordDirectory 'web-bookmarks--tampermonkey.json'
        Write-DeploymentJson $recordPath $record
        $saved = Read-DeploymentJson $recordPath
        foreach ($key in $record.Keys) {
            if ($saved[$key] -cne $record[$key]) { throw "Release record verification failed for $key." }
        }
        $record
    } finally {
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $repository = Split-Path -Parent $PSScriptRoot
    $deployment = Join-Path (Split-Path -Parent $repository) 'solution-deploy\src\CommonRelease.psm1'
    Import-Module $deployment -DisableNameChecking
    Import-Module (Join-Path (Split-Path -Parent $deployment) 'Deployment.psm1') -DisableNameChecking
    Invoke-UserscriptRelease -Repository $repository -Commit $Commit -VerifyOnly:$VerifyOnly `
        -RecordDirectory $RecordDirectory
}
