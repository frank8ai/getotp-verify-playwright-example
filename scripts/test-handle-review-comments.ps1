param(
    [string]$HandlerScript = ".\scripts\handle-review-comments.ps1"
)

$ErrorActionPreference = "Stop"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

Assert-True (Test-Path -LiteralPath $HandlerScript) "Missing handler script: $HandlerScript"

# 1. Test unauthorized user block
$unauthOut = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $HandlerScript -CommentBody "@aer-bot review" -CommentAuthor "untrusted-user" -AuthorAssociation "NONE" 2>&1
$unauthText = ($unauthOut | Out-String).Trim()
Assert-True ($unauthText -match "UNAUTHORIZED") "Untrusted user should be rejected, output=$unauthText"

# 2. Test authorized PR author @aer-bot review
$authorOut = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $HandlerScript -CommentBody "@aer-bot review" -CommentAuthor "frank8ai" -IsPrAuthor -PrNumber 1 2>&1
$authorText = ($authorOut | Out-String).Trim()
Assert-True ($authorText -match "HANDLE_REVIEW_COMMENTS_OK status=DISPATCHED") "Author review should be dispatched, output=$authorText"
Assert-True ($authorText -match "Triggered AER native code review") "Message mismatch, output=$authorText"

# 3. Test collaborator @aer-bot explain
$explainOut = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $HandlerScript -CommentBody "@aer-bot explain GetOTPClient" -CommentAuthor "teammate" -AuthorAssociation "COLLABORATOR" -PrNumber 1 2>&1
$explainText = ($explainOut | Out-String).Trim()
Assert-True ($explainText -match "DISPATCH: explain \(target=GetOTPClient\)") "Target explain should be dispatched, output=$explainText"

Write-Host "HANDLE_REVIEW_COMMENTS_TEST_OK"
exit 0
