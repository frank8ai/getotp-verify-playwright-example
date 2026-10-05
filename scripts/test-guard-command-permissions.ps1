param(
    [string]$GuardScript = ".\scripts\guard-command-permissions.ps1"
)

$ErrorActionPreference = "Stop"

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }

Assert-True (Test-Path -LiteralPath $GuardScript) "Missing guard script: $GuardScript"

# Case 1: Unauthorized external commenter
$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$unauthOut = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $GuardScript -CommentAuthor "random-user" -AuthorAssociation "NONE" -CommentBody "@aer-bot fix" 2>&1
$unauthExit = $LASTEXITCODE
$ErrorActionPreference = $prev

Assert-True ($unauthExit -eq 2) "External commenter must be denied with exit 2, got $unauthExit"
Assert-True (($unauthOut | Out-String) -match "GUARD: DENIED") "Expected DENIED log"

# Case 2: Authorized collaborator with @aer-bot review
$authOut = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $GuardScript -CommentAuthor "frank8ai" -AuthorAssociation "OWNER" -CommentBody "@aer-bot review" 2>&1
$authExit = $LASTEXITCODE
$authText = ($authOut | Out-String).Trim()

Assert-True ($authExit -eq 0) "Owner must be authorized with exit 0, got $authExit"
Assert-True ($authText -match "GUARD: AUTHORIZED") "Expected AUTHORIZED log"
Assert-True ($authText -match '"command":\s*"review"') "Expected parsed command 'review'"

# Case 3: Checkbox interaction [x] Apply fix
$boxOut = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $GuardScript -CommentAuthor "team-member" -AuthorAssociation "COLLABORATOR" -CommentBody "- [x] Apply fix for finding #1" 2>&1
$boxExit = $LASTEXITCODE
$boxText = ($boxOut | Out-String).Trim()

Assert-True ($boxExit -eq 0) "Collaborator must be authorized, got $boxExit"
Assert-True ($boxText -match '"command":\s*"fix"') "Expected parsed command 'fix'"

# Case 4: Authorized collaborator with @aer-bot merge
$mergeAuthOut = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $GuardScript -CommentAuthor "frank8ai" -AuthorAssociation "OWNER" -CommentBody "@aer-bot merge" 2>&1
$mergeAuthExit = $LASTEXITCODE
$mergeAuthText = ($mergeAuthOut | Out-String).Trim()

Assert-True ($mergeAuthExit -eq 0) "Owner merge must be authorized, got $mergeAuthExit"
Assert-True ($mergeAuthText -match '"command":\s*"merge"') "Expected parsed command 'merge'"

# Case 5: Unauthorized external user attempting @aer-bot merge (越权)
$prev = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$mergeUnauthOut = & PowerShell -NoProfile -ExecutionPolicy Bypass -File $GuardScript -CommentAuthor "attacker" -AuthorAssociation "NONE" -CommentBody "@aer-bot merge" 2>&1
$mergeUnauthExit = $LASTEXITCODE
$ErrorActionPreference = $prev

Assert-True ($mergeUnauthExit -eq 2) "External user merge attempt must be denied with exit 2, got $mergeUnauthExit"
Assert-True (($mergeUnauthOut | Out-String) -match "GUARD: DENIED") "Expected DENIED log on unauthorized merge"

Write-Host "GUARD_COMMAND_PERMISSIONS_TEST_OK"
exit 0
