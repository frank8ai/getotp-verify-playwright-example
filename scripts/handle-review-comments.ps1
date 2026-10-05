<#
.SYNOPSIS
    Parses and handles GitHub PR/Issue comments and checkbox interactions for AER in getotp-verify-playwright-example.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$CommentBody,

    [Parameter(Mandatory = $true)]
    [string]$CommentAuthor,

    [string]$AuthorAssociation = "NONE",
    [string]$Repo = "frank8ai/getotp-verify-playwright-example",
    [int]$PrNumber = 0,
    [switch]$IsPrAuthor,
    [string]$PrJsonPath = "",
    [string]$ReviewJsonPath = "",
    [string]$ShipReadinessPath = "",
    [string]$ExpectedHeadSha = "",
    [string]$PrBaseRef = "",
    [switch]$Execute,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$performActions = $Execute -and -not $DryRun

$result = [ordered]@{
    authorized = $false
    command = $null
    args = @()
    checkboxActions = @()
    status = "IGNORED"
    message = ""
}

$privilegedRoles = @("OWNER", "MEMBER", "COLLABORATOR")
$associationUpper = if ($AuthorAssociation) { $AuthorAssociation.ToUpperInvariant() } else { "NONE" }
$isCollaborator = $privilegedRoles -contains $associationUpper

$matchedCmd = $null
$argsList = @()

if ($CommentBody -match "(?im)@aer-bot\s+(review|fix|explain|ignore|merge)\b(.*)$") {
    $matchedCmd = $Matches[1].ToLowerInvariant()
    $rawArgs = $Matches[2].Trim()
    if ($rawArgs) {
        $argsList = @($rawArgs -split "\s+")
    }
} elseif ($CommentBody -match "\[x\]\s*Apply fix") {
    $matchedCmd = "fix"
    $argsList = @("all")
}

$checkboxMatches = [regex]::Matches($CommentBody, '(?m)^\s*-\s*\[[xX]\]\s*(.+)$')
foreach ($match in $checkboxMatches) {
    $itemText = $match.Groups[1].Value.Trim()
    $result.checkboxActions += $itemText
}

$isAuthorized = $false
if ($matchedCmd -eq "merge") {
    $isAuthorized = $isCollaborator
} else {
    $isAuthorized = $isCollaborator -or $IsPrAuthor
}

if (-not $isAuthorized) {
    $result.status = "UNAUTHORIZED"
    $result.message = "Commenter '$CommentAuthor' lacks required permissions (association: $associationUpper, isPrAuthor: $IsPrAuthor)."
    Write-Warning $result.message
    $result | ConvertTo-Json -Depth 5
    exit 0
}

$result.authorized = $true
$result.command = $matchedCmd
$result.args = $argsList

if ($matchedCmd) {
    switch ($matchedCmd) {
        "review" {
            $result.status = "DISPATCHED"
            $result.message = "Triggered AER native code review for PR #$PrNumber"
            Write-Host "DISPATCH: review on $Repo#$PrNumber"

            if ($performActions -and $PrNumber -gt 0) {
                $reportPath = Join-Path ([IO.Path]::GetTempPath()) ("aer-perspective-" + [guid]::NewGuid().ToString("N") + ".md")
                try {
                    $baseRef = $PrBaseRef
                    if (-not $baseRef) {
                        $baseRef = (& gh pr view $PrNumber --repo $Repo --json baseRefName --jq ".baseRefName" 2>&1 | Out-String).Trim()
                    }
                    if (-not $baseRef -or $baseRef -notmatch "^[A-Za-z0-9._/-]+$") { $baseRef = "main" }

                    Write-Host "Checking out PR #$PrNumber head for review..."
                    & gh pr checkout $PrNumber --repo $Repo --detach 2>&1 | Write-Host

                    Write-Host "Regenerating perspective report for $Repo#$PrNumber (base=origin/$baseRef)..."
                    & python -m aer review perspective --mode range --from "origin/$baseRef" --to "HEAD" --output $reportPath 2>&1 | Write-Host

                    if (Test-Path -LiteralPath $reportPath) {
                        $publishScript = Join-Path $PSScriptRoot "publish-pr-review.ps1"
                        & PowerShell -NoProfile -ExecutionPolicy Bypass -File $publishScript -Repo $Repo -PrNumber $PrNumber -PerspectiveReportPath $reportPath 2>&1 | Write-Host
                        $result.reviewPublished = ($LASTEXITCODE -eq 0)
                    } else {
                        Write-Warning "Perspective report was not produced; nothing published."
                        $result.reviewPublished = $false
                    }
                } catch {
                    Write-Warning "review dispatch failed: $_"
                    $result.reviewPublished = $false
                } finally {
                    if (Test-Path -LiteralPath $reportPath) { Remove-Item -LiteralPath $reportPath -Force -ErrorAction SilentlyContinue }
                }
            }
        }
        "explain" {
            $target = if ($argsList.Count -gt 0) { $argsList -join " " } else { "entire diff" }
            $result.status = "DISPATCHED"
            $result.message = "Triggered context explanation for: $target on PR #$PrNumber"
            Write-Host "DISPATCH: explain (target=$target) on $Repo#$PrNumber"

            if ($performActions -and $PrNumber -gt 0 -and $argsList.Count -gt 0) {
                $symbol = $argsList[0]
                $explainPath = Join-Path ([IO.Path]::GetTempPath()) ("aer-explain-" + [guid]::NewGuid().ToString("N") + ".md")
                try {
                    & python -m aer review explain --symbol $symbol --repo . --output $explainPath 2>&1 | Write-Host
                    if (Test-Path -LiteralPath $explainPath) {
                        & gh pr comment $PrNumber --repo $Repo --body-file $explainPath 2>&1 | Write-Host
                        $result.explainPosted = ($LASTEXITCODE -eq 0)
                    } else {
                        Write-Warning "Symbol explanation was not produced; nothing posted."
                        $result.explainPosted = $false
                    }
                } catch {
                    Write-Warning "explain dispatch failed: $_"
                    $result.explainPosted = $false
                } finally {
                    if (Test-Path -LiteralPath $explainPath) { Remove-Item -LiteralPath $explainPath -Force -ErrorAction SilentlyContinue }
                }
            }
        }
        "ignore" {
            $target = if ($argsList.Count -gt 0) { $argsList[0] } else { "unspecified" }
            $result.status = "ACKNOWLEDGED"
            $result.message = "Finding $target marked as ignored for PR #$PrNumber"
            Write-Host "DISPATCH: ignore (target=$target) on $Repo#$PrNumber"
        }
        "fix" {
            $target = if ($argsList.Count -gt 0) { $argsList[0] } else { "all" }
            $result.status = "DISPATCHED"
            $result.message = "Triggered autonomous fix loop for target: $target on PR #$PrNumber"
            Write-Host "DISPATCH: fix (target=$target) on $Repo#$PrNumber"
        }
        "merge" {
            Write-Host "DISPATCH: merge on $Repo#$PrNumber"
            $result.status = "DISPATCHED"
            $result.message = "Evaluated merge command for PR #$PrNumber"
        }
        default {
            $result.status = "UNKNOWN_COMMAND"
            $result.message = "Unrecognized command '@aer-bot $matchedCmd'"
            Write-Warning "Unknown command: $matchedCmd"
        }
    }
} elseif ($result.checkboxActions.Count -gt 0) {
    $result.status = "CHECKBOX_HANDLED"
    $result.message = "Parsed $($result.checkboxActions.Count) checked checkbox action(s)."
} else {
    $result.status = "NO_ACTION"
    $result.message = "No @aer-bot commands or checkbox toggles found."
}

Write-Host "HANDLE_REVIEW_COMMENTS_OK status=$($result.status)"
$result | ConvertTo-Json -Depth 5
exit 0
