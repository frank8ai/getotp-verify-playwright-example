param(
    [string]$PublishScript = ".\scripts\publish-pr-review.ps1"
)

$ErrorActionPreference = "Stop"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $PublishScript) "Missing publish script: $PublishScript"

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("test-publish-pr-review-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    # 1. Test parameter validation
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $missingArgs = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $PublishScript -Repo "frank8ai/aer-runtime" -PrNumber 27 2>&1
    $ErrorActionPreference = $prev
    Assert-True ($LASTEXITCODE -ne 0) "Should fail when neither report nor json path is provided"

    # 2. Test markdown report dry-run
    $sampleMd = Join-Path $tempDir "sample-report.md"
    $mdBody = "<!-- aer-review-perspective -->`n## AER Review Perspective`nAll clean!"
    [System.IO.File]::WriteAllText($sampleMd, $mdBody, [System.Text.Encoding]::UTF8)

    $out1 = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $PublishScript -Repo "frank8ai/aer-runtime" -PrNumber 27 -PerspectiveReportPath $sampleMd -DryRun 2>&1
    $text1 = ($out1 | Out-String).Trim()
    Assert-True ($LASTEXITCODE -eq 0) "DryRun with markdown should succeed, exit=$LASTEXITCODE, output=$text1"
    Assert-True ($text1 -match "PUBLISH_PR_REVIEW_OK") "Expected success marker, output=$text1"
    Assert-True ($text1 -match "DRY_RUN") "Expected dry run execution trace, output=$text1"

    # 3. Test JSON report dry-run with inline comments
    $sampleJson = Join-Path $tempDir "sample-report.json"
    $jsonObj = [ordered]@{
        summaryText = "Found 1 issue"
        decision = "CHANGES_REQUESTED"
        coverageRate = 1.0
        reviewedCount = 1
        skippedCount = 0
        blockingCount = 1
        markdown = "<!-- aer-review-perspective -->`n## AER Review"
        findings = @(
            [ordered]@{
                path = "core/aer/review/perspective.py"
                content = "Missing validation"
                severity = "high"
                category = "bug"
                position = "resolved"
                start_line = 10
                end_line = 10
                inlineComment = "HIGH: Missing validation"
            }
        )
    }
    $jsonText = $jsonObj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($sampleJson, $jsonText, [System.Text.Encoding]::UTF8)

    $out2 = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $PublishScript -Repo "frank8ai/aer-runtime" -PrNumber 27 -PerspectiveJsonPath $sampleJson -CommitSha "abc1234567890abcdef" -PublishInline -DryRun 2>&1
    $text2 = ($out2 | Out-String).Trim()
    Assert-True ($LASTEXITCODE -eq 0) "DryRun with JSON and inline should succeed, exit=$LASTEXITCODE, output=$text2"
    Assert-True ($text2 -match "INLINE_COMMENTS_PROCESSED published=1") "Expected 1 published inline comment in dry run, output=$text2"
    Assert-True ($text2 -match "PUBLISH_PR_REVIEW_OK") "Expected success marker, output=$text2"
    # 4. Test unauthenticated / bad credentials must exit non-zero (throw).
    # The invalid credential is generated rather than written as a literal: a
    # credential-shaped string in the tree is reported by
    # scripts/scan-backup-secrets.ps1, and that scanner deliberately has no
    # allowlist to hide behind. Any non-token string is rejected the same way.
    $invalidCredential = [Guid]::NewGuid().ToString("N")
    $prevToken = $env:GH_TOKEN
    try {
        $env:GH_TOKEN = $invalidCredential
        $prevErr = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $unauthOut = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $PublishScript -Repo "frank8ai/aer-runtime" -PrNumber 27 -PerspectiveReportPath $sampleMd 2>&1
        $ErrorActionPreference = $prevErr
        $unauthText = ($unauthOut | Out-String).Trim()
        Assert-True ($LASTEXITCODE -ne 0) "Unauthenticated call must exit non-zero, exit=$LASTEXITCODE, output=$unauthText"
        Assert-True ($unauthText -match "gh API call failed|Bad credentials|HTTP 401") "Expected failure message on unauthenticated API call, output=$unauthText"
    } finally {
        $env:GH_TOKEN = $prevToken
    }
}
finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "PUBLISH_PR_REVIEW_TEST_OK"
exit 0
