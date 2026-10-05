<#
.SYNOPSIS
    Publishes or updates a CodeRabbit-grade AER Review Perspective report and line-level comments on a GitHub PR.

.DESCRIPTION
    1. Top-level Perspective Report: Idempotently creates or updates (upserts) the top-level PR comment
       using the stable anchor <!-- aer-review-perspective -->.
    2. Inline Review Comments: Publishes line-level suggestion comments on added lines for resolved findings,
       avoiding duplicate comments if an identical recommendation already exists.

.PARAMETER Repo
    Target GitHub repository in "owner/repo" format.

.PARAMETER PrNumber
    The pull request number.

.PARAMETER PerspectiveReportPath
    Path to the Markdown file containing the perspective report (optional if PerspectiveJsonPath is provided).

.PARAMETER PerspectiveJsonPath
    Path to the JSON file containing the PerspectiveReport data (optional if PerspectiveReportPath is provided).

.PARAMETER CommitSha
    The HEAD commit SHA of the pull request (required for inline line-level comments).

.PARAMETER PublishInline
    Switch to enable publishing line-level inline review comments.

.PARAMETER DryRun
    Simulate API calls without mutating GitHub state.
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Repo,

    [Parameter(Mandatory = $true)]
    [int]$PrNumber,

    [string]$PerspectiveReportPath = "",
    [string]$PerspectiveJsonPath = "",
    [string]$CommitSha = "",
    [switch]$PublishInline,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$ANCHOR = "<!-- aer-review-perspective -->"

function Invoke-GhApi {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & gh @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $msg = ($output | Out-String).Trim()
        throw "gh API call failed (exit $exitCode): $msg"
    }
    return ($output | Out-String)
}

if (-not $PerspectiveReportPath -and -not $PerspectiveJsonPath) {
    [Console]::Error.WriteLine("Either -PerspectiveReportPath or -PerspectiveJsonPath must be specified")
    exit 1
}

$markdownContent = ""
$reportData = $null

if ($PerspectiveJsonPath) {
    if (-not (Test-Path -LiteralPath $PerspectiveJsonPath)) {
        throw "Perspective JSON file not found: $PerspectiveJsonPath"
    }
    $reportData = Get-Content -Raw -LiteralPath $PerspectiveJsonPath -Encoding UTF8 | ConvertFrom-Json
    if ($reportData.PSObject.Properties.Name -contains "markdown") {
        $markdownContent = [string]$reportData.markdown
    }
}

if (-not $markdownContent -and $PerspectiveReportPath) {
    if (-not (Test-Path -LiteralPath $PerspectiveReportPath)) {
        throw "Perspective report file not found: $PerspectiveReportPath"
    }
    $markdownContent = Get-Content -Raw -LiteralPath $PerspectiveReportPath -Encoding UTF8
}

if (-not $markdownContent) {
    throw "No markdown content could be resolved for the perspective report"
}

if ($markdownContent -notmatch [regex]::Escape($ANCHOR)) {
    $markdownContent = "$ANCHOR`n`n" + $markdownContent.Trim()
}

Write-Host "Publishing perspective report to $Repo#$PrNumber..."

# --- Step 1: Idempotent Top-level Perspective Comment (Upsert via Anchor) ---
$existingCommentId = $null
if ($DryRun) {
    Write-Host "DRY_RUN: gh api repos/$Repo/issues/$PrNumber/comments?per_page=100"
} else {
    $commentsRaw = Invoke-GhApi -Arguments @("api", "repos/$Repo/issues/$PrNumber/comments?per_page=100")
    if ($commentsRaw) {
        $comments = $commentsRaw | ConvertFrom-Json
        foreach ($c in @($comments)) {
            if ($c.body -match [regex]::Escape($ANCHOR)) {
                $existingCommentId = $c.id
                break
            }
        }
    }
}

if ($existingCommentId) {
    Write-Host "Found existing perspective comment (id: $existingCommentId). Updating in place..."
    if ($DryRun) {
        Write-Host "DRY_RUN: gh api -X PATCH repos/$Repo/issues/comments/$existingCommentId -f body=<redacted>"
    } else {
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $payloadObj = @{ body = $markdownContent }
            $jsonPayload = $payloadObj | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($tempFile, $jsonPayload, [System.Text.UTF8Encoding]::new($false))
            $null = Invoke-GhApi -Arguments @("api", "--method", "PATCH", "repos/$Repo/issues/comments/$existingCommentId", "--input", $tempFile)
            Write-Host "TOP_LEVEL_PERSPECTIVE_UPDATED id=$existingCommentId"
        } finally {
            if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }
} else {
    Write-Host "No existing perspective comment found. Creating new top-level comment..."
    if ($DryRun) {
        Write-Host "DRY_RUN: gh api -X POST repos/$Repo/issues/$PrNumber/comments -f body=<redacted>"
    } else {
        $tempFile = [System.IO.Path]::GetTempFileName()
        try {
            $payloadObj = @{ body = $markdownContent }
            $jsonPayload = $payloadObj | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($tempFile, $jsonPayload, [System.Text.UTF8Encoding]::new($false))
            $createdRaw = Invoke-GhApi -Arguments @("api", "--method", "POST", "repos/$Repo/issues/$PrNumber/comments", "--input", $tempFile)
            $created = $createdRaw | ConvertFrom-Json
            if (-not $created -or -not $created.id) {
                throw "Top-level perspective comment creation failed: missing comment id in API response"
            }
            Write-Host "TOP_LEVEL_PERSPECTIVE_CREATED id=$($created.id)"
        } finally {
            if (Test-Path -LiteralPath $tempFile) { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
        }
    }
}

# --- Step 2: Inline Line-level Comments (Optional) ---
if ($PublishInline -and $reportData -and $reportData.findings) {
    if (-not $CommitSha) {
        Write-Warning "CommitSha is required to publish inline comments; skipping inline publishing."
    } else {
        Write-Host "Checking inline findings for publishing..."
        $existingReviews = @()
        if ($DryRun) {
            Write-Host "DRY_RUN: gh api repos/$Repo/pulls/$PrNumber/comments?per_page=100"
        } else {
            $reviewsRaw = Invoke-GhApi -Arguments @("api", "repos/$Repo/pulls/$PrNumber/comments?per_page=100")
            if ($reviewsRaw) {
                $existingReviews = @($reviewsRaw | ConvertFrom-Json)
            }
        }

        $publishedCount = 0
        foreach ($f in @($reportData.findings)) {
            if ($f.position -ne "resolved" -or -not $f.start_line -or $f.start_line -le 0) {
                continue
            }
            $filePath = [string]$f.path
            $lineNum = [int]$f.start_line
            $body = if ($f.inlineComment) { [string]$f.inlineComment } else { [string]$f.content }

            # Deduplication check: see if a comment with similar content already exists on this line & file
            $isDuplicate = $false
            foreach ($ec in $existingReviews) {
                if ($ec.path -eq $filePath -and [int]$ec.line -eq $lineNum) {
                    if ($ec.body -match [regex]::Escape($f.content)) {
                        $isDuplicate = $true
                        break
                    }
                }
            }

            if ($isDuplicate) {
                Write-Host "Skipping duplicate inline comment at $filePath`:$lineNum"
                continue
            }

            Write-Host "Publishing inline comment at $filePath`:$lineNum..."
            if ($DryRun) {
                Write-Host "DRY_RUN: gh api repos/$Repo/pulls/$PrNumber/comments (path=$filePath, line=$lineNum, commit_id=$CommitSha)"
                $publishedCount++
            } else {
                $payloadObj = @{
                    body = $body
                    commit_id = $CommitSha
                    path = $filePath
                    line = $lineNum
                    side = "RIGHT"
                }
                $tempInlineFile = [System.IO.Path]::GetTempFileName()
                try {
                    $payloadObj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tempInlineFile -Encoding UTF8
                    $null = Invoke-GhApi -Arguments @("api", "--method", "POST", "repos/$Repo/pulls/$PrNumber/comments", "--input", $tempInlineFile)
                    $publishedCount++
                } finally {
                    if (Test-Path -LiteralPath $tempInlineFile) { Remove-Item -LiteralPath $tempInlineFile -Force -ErrorAction SilentlyContinue }
                }
            }
        }
        Write-Host "INLINE_COMMENTS_PROCESSED published=$publishedCount"
    }
}

Write-Host "PUBLISH_PR_REVIEW_OK"
exit 0
