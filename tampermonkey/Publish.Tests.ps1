$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path (Split-Path -Parent $root) 'solution-deploy\src\CommonRelease.psm1') -DisableNameChecking
Import-Module (Join-Path (Split-Path -Parent $root) 'solution-deploy\src\Deployment.psm1') -DisableNameChecking
. (Join-Path $PSScriptRoot 'Publish.ps1')

function Assert-PublishThrows([scriptblock]$Action, [string]$Message) {
    $caught = $null
    try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
    ($null -ne $caught) | Should Be $true
    $caught | Should BeLike $Message
}

Describe 'Userscript publication and release records' {
    BeforeEach {
        $script:commitId = 'a' * 40
        $script:headerText = "// ==UserScript==`n// @version      4.9.39`n// ==/UserScript=="
        $script:bundleText = "$script:headerText`nconsole.log('palette');`n"
        $script:remoteText = $script:bundleText.Replace('4.9.39', '4.9.38')
        $script:latestText = $script:remoteText
        $script:releaseDetails = @{
            tagName = 'tampermonkey-v4.9.38'
            publishedAt = '2026-10-30T19:20:53Z'
        }
        $script:latestTag = $script:releaseDetails.tagName
        $script:releaseList = @(@{ tagName = $script:releaseDetails.tagName; publishedAt = $script:releaseDetails.publishedAt })
        $script:createRelease = $false
        $script:failReleaseCreation = $false
        $script:skipReleaseUpdate = $false
        $script:records = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        Mock Resolve-CommonReleaseSource { $script:commitId }
        Mock Invoke-UserscriptTool {
            if ($Name -eq 'git') {
                $output = $Arguments | Where-Object { $_ -like '--output=*' }
                $zip = [IO.Compression.ZipFile]::Open($output.Substring(9), 'Create')
                try {
                    foreach ($entry in @(
                        @{ name = 'tampermonkey/webbookmarks-palette.user.js'; text = $script:bundleText },
                        @{ name = 'tampermonkey/src/header.txt'; text = $script:headerText }
                    )) {
                        $writer = [IO.StreamWriter]::new($zip.CreateEntry($entry.name).Open())
                        try { $writer.Write($entry.text) } finally { $writer.Dispose() }
                    }
                } finally { $zip.Dispose() }
            } elseif ($Name -eq 'gh' -and $Arguments[0] -eq 'release' -and $Arguments[1] -eq 'create') {
                if ($script:failReleaseCreation) { throw 'Release creation failed' }
                $script:createRelease = $true
                if (-not $script:skipReleaseUpdate) {
                    $script:releaseDetails = @{
                        tagName = $Arguments[2]
                        publishedAt = '2026-11-20T16:30:00Z'
                    }
                    $script:latestTag = $Arguments[2]
                    $script:remoteText = $script:bundleText
                    $script:latestText = $script:bundleText
                }
            } else { throw "Unexpected tool $Name" }
        }
        Mock Get-UserscriptReleases { $script:releaseList }
        Mock Get-UserscriptReleaseDetails { $script:releaseDetails }
        Mock Get-UserscriptLatestTag { $script:latestTag }
        Mock Get-UserscriptRaw { $script:remoteText }
        Mock Get-UserscriptLatestRaw { $script:latestText }
    }

    It 'records an existing release with its real publication time without uploading' {
        $script:releaseDetails.tagName = 'tampermonkey-v4.9.39'
        $script:latestTag = $script:releaseDetails.tagName
        $script:releaseList = @(@{ tagName = $script:releaseDetails.tagName; publishedAt = $script:releaseDetails.publishedAt })
        $script:remoteText = $script:bundleText
        $script:latestText = $script:bundleText
        $result = Invoke-UserscriptRelease $root HEAD -VerifyOnly -RecordDirectory $script:records
        $result.component | Should Be tampermonkey
        $result.sourceCommit | Should Be $script:commitId
        $result.version | Should Be '4.9.39'
        $result.releaseTag | Should Be 'tampermonkey-v4.9.39'
        ([DateTimeOffset]::Parse($result.completedLocal).ToUnixTimeSeconds()) | Should Be ([DateTimeOffset]::Parse('2026-10-30T19:20:53Z').ToUnixTimeSeconds())
        (Read-DeploymentJson (Join-Path $script:records 'web-bookmarks--tampermonkey.json')).sourceCommit | Should Be $script:commitId
        Assert-MockCalled Invoke-UserscriptTool -Times 0 -Exactly -Scope It -ParameterFilter { $Name -eq 'gh' }
    }

    It 'publishes a higher version and verifies it before recording' {
        (Invoke-UserscriptRelease $root HEAD -RecordDirectory $script:records).version | Should Be '4.9.39'
        $script:createRelease | Should Be $true
        (Read-DeploymentJson (Join-Path $script:records 'web-bookmarks--tampermonkey.json')).releaseTag | Should Be 'tampermonkey-v4.9.39'
        Assert-MockCalled Invoke-UserscriptTool -Times 1 -Exactly -Scope It -ParameterFilter { $Name -eq 'gh' -and $Arguments[1] -eq 'create' }
    }

    It 'accepts identical content with CRLF without republishing' {
        $script:releaseDetails.tagName = 'tampermonkey-v4.9.39'
        $script:latestTag = $script:releaseDetails.tagName
        $script:releaseList = @(@{ tagName = $script:releaseDetails.tagName; publishedAt = $script:releaseDetails.publishedAt })
        $script:remoteText = $script:bundleText.Replace("`n", "`r`n")
        $script:latestText = $script:remoteText
        Invoke-UserscriptRelease $root HEAD -RecordDirectory $script:records | Out-Null
        $script:createRelease | Should Be $false
    }

    It 'refuses to record when the stable latest URL serves another asset' {
        $script:releaseDetails.tagName = 'tampermonkey-v4.9.39'
        $script:latestTag = $script:releaseDetails.tagName
        $script:releaseList = @(@{ tagName = $script:releaseDetails.tagName; publishedAt = $script:releaseDetails.publishedAt })
        $script:remoteText = $script:bundleText
        $script:latestText = $script:bundleText + '// stale latest asset'
        Assert-PublishThrows { Invoke-UserscriptRelease $root HEAD -VerifyOnly -RecordDirectory $script:records } '*Latest GitHub Release URL did not verify*'
        Test-Path $script:records | Should Be $false
    }

    It 'decodes GitHub Release assets returned as UTF-8 bytes' {
        $content = "// @version 4.9.43`n"
        (ConvertTo-UserscriptText ([Text.Encoding]::UTF8.GetBytes($content))) | Should Be $content
    }

    It 'rejects changed content without a higher version' {
        $script:releaseDetails.tagName = 'tampermonkey-v4.9.39'
        $script:latestTag = $script:releaseDetails.tagName
        $script:releaseList = @(@{ tagName = $script:releaseDetails.tagName; publishedAt = $script:releaseDetails.publishedAt })
        $script:remoteText = $script:bundleText + '// different'
        Assert-PublishThrows { Invoke-UserscriptRelease $root HEAD -RecordDirectory $script:records } '*Increase @version*'
        Test-Path $script:records | Should Be $false
    }

    It 'refuses to record a mismatched release in verify-only mode' {
        $script:releaseDetails.tagName = 'tampermonkey-v4.9.39'
        $script:latestTag = $script:releaseDetails.tagName
        $script:releaseList = @(@{ tagName = $script:releaseDetails.tagName; publishedAt = $script:releaseDetails.publishedAt })
        $script:remoteText = $script:bundleText + '// different'
        Assert-PublishThrows { Invoke-UserscriptRelease $root HEAD -VerifyOnly -RecordDirectory $script:records } '*differs from the committed bundle*'
        Test-Path $script:records | Should Be $false
    }

    It 'does not record a failed or unverified release' {
        $script:failReleaseCreation = $true
        Assert-PublishThrows { Invoke-UserscriptRelease $root HEAD -RecordDirectory $script:records } '*Release creation failed*'
        Test-Path $script:records | Should Be $false
        $script:failReleaseCreation = $false
        $script:skipReleaseUpdate = $true
        $script:releaseDetails.tagName = 'tampermonkey-v4.9.39'
        $script:latestTag = $script:releaseDetails.tagName
        $script:releaseList = @()
        $script:remoteText = $script:bundleText.Replace('4.9.39', '4.9.38')
        Assert-PublishThrows { Invoke-UserscriptRelease $root HEAD -RecordDirectory $script:records } '*asset did not verify*'
        Test-Path $script:records | Should Be $false
    }

    It 'fails explicitly on release-record write failure' {
        Mock Write-DeploymentJson { throw 'Record denied' }
        Assert-PublishThrows { Invoke-UserscriptRelease $root HEAD -RecordDirectory $script:records } '*Record denied*'
    }

    It 'rejects mismatched committed metadata before contacting GitHub Releases' {
        $script:headerText = $script:headerText.Replace('4.9.39', '4.9.40')
        Assert-PublishThrows { Invoke-UserscriptRelease $root HEAD -RecordDirectory $script:records } '*Rebuild and commit first*'
        Assert-MockCalled Get-UserscriptReleases -Times 0 -Exactly -Scope It
    }
}

Describe 'Committed userscript extraction with real Git' {
    It 'exports the exact committed bundle and header as nonempty archive entries' {
        $archive = Join-Path $TestDrive 'real-userscript.zip'
        Invoke-UserscriptTool git @('archive', '--format=zip', "--output=$archive", 'HEAD',
            'tampermonkey/webbookmarks-palette.user.js', 'tampermonkey/src/header.txt') $root
        $zip = [IO.Compression.ZipFile]::OpenRead($archive)
        try {
            $texts = @{}
            foreach ($name in 'tampermonkey/webbookmarks-palette.user.js', 'tampermonkey/src/header.txt') {
                $reader = [IO.StreamReader]::new($zip.GetEntry($name).Open())
                try { $texts[$name] = $reader.ReadToEnd().Replace("`r`n", "`n") } finally { $reader.Dispose() }
            }
            $bundle = $texts['tampermonkey/webbookmarks-palette.user.js']
            $header = $texts['tampermonkey/src/header.txt'].TrimEnd()
            $bundle.Length | Should BeGreaterThan 1000
            $bundle.StartsWith($header + "`n") | Should Be $true
        } finally { $zip.Dispose() }
    }
}
