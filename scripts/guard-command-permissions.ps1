param(
    [string]$PayloadPath = "",
    [string]$CommentAuthor = "",
    [string]$AuthorAssociation = "",
    [string]$CommentBody = ""
)

$ErrorActionPreference = "Stop"

$ALLOWED_ASSOCIATIONS = @("OWNER", "MEMBER", "COLLABORATOR")

if ($PayloadPath) {
    if (-not (Test-Path -LiteralPath $PayloadPath)) {
        throw "Payload file not found: $PayloadPath"
    }
    $payload = Get-Content -Raw -LiteralPath $PayloadPath -Encoding UTF8 | ConvertFrom-Json
    $comment = if ($payload.comment) { $payload.comment } else { $payload }
    if (-not $CommentAuthor -and $comment.user) {
        $CommentAuthor = [string]$comment.user.login
    }
    if (-not $AuthorAssociation -and $comment.author_association) {
        $AuthorAssociation = [string]$comment.author_association
    }
    if (-not $CommentBody -and $comment.body) {
        $CommentBody = [string]$comment.body
    }
}

if (-not $AuthorAssociation) {
    $AuthorAssociation = ""
}
$AuthorAssociation = $AuthorAssociation.ToUpperInvariant()

Write-Host "GUARD: Checking permissions for author='$CommentAuthor', association='$AuthorAssociation'..."

$isAuthorized = $AuthorAssociation -in $ALLOWED_ASSOCIATIONS
if (-not $isAuthorized) {
    [Console]::Error.WriteLine("GUARD: DENIED. User '$CommentAuthor' ($AuthorAssociation) is not an authorized collaborator.")
    exit 2
}

Write-Host "GUARD: AUTHORIZED ($AuthorAssociation)"

# Command parsing
$matchedCommand = $null
$commandArgs = @()

if ($CommentBody -match "(?im)@aer-bot\s+(review|fix|explain|ignore|merge)\b(.*)$") {
    $matchedCommand = $Matches[1].ToLowerInvariant()
    $rawArgs = $Matches[2].Trim()
    if ($rawArgs) {
        $commandArgs = $rawArgs -split "\s+"
    }
} elseif ($CommentBody -match "\[x\]\s*Apply fix") {
    $matchedCommand = "fix"
    $commandArgs = @("all")
}

$result = [ordered]@{
    authorized = $true
    author = $CommentAuthor
    association = $AuthorAssociation
    command = $matchedCommand
    arguments = $commandArgs
}

Write-Host "GUARD_COMMAND_RESULT:"
$result | ConvertTo-Json -Depth 5
exit 0
