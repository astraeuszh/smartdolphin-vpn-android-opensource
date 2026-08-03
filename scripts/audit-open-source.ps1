[CmdletBinding()]
param(
  [string]$ReportPath = ".audit/open-source-audit-report.json",
  [switch]$IncludeHistory
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$report = Join-Path $root $ReportPath
$reportDir = Split-Path -Parent $report
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

$patterns = @(
  @{ Name = 'private-key'; Regex = '-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----' },
  @{ Name = 'generic-secret-assignment'; Regex = '(?i)(?:api[_-]?key|secret|password|client[_-]?secret|access[_-]?token)\s*[:=]\s*\S{12,}' },
  @{ Name = 'bearer-token'; Regex = '(?i)bearer\s+[A-Za-z0-9._\-]{16,}' },
  @{ Name = 'ipv4-address'; Regex = '(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])' },
  @{ Name = 'public-url'; Regex = '(?i)https?://\S+' },
  @{ Name = 'project-identifier'; Regex = '(?i)astraeus\.smartdolphin|smartdolphinvpn|smartdolphin' }
)

$extensions = @('.dart', '.kt', '.java', '.go', '.xml', '.yaml', '.yml', '.json', '.properties', '.gradle', '.kts', '.md', '.txt', '.sh', '.ps1')
$files = Get-ChildItem -Path $root -Recurse -File -Force | Where-Object {
  $_.FullName -notmatch '\\(\.git|\.dart_tool|\.gradle|build|archive|artifacts|\.audit)\\' -and $extensions -contains $_.Extension
}

$findings = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
  foreach ($pattern in $patterns) {
    Select-String -LiteralPath $file.FullName -Pattern $pattern.Regex -AllMatches | ForEach-Object {
      foreach ($match in $_.Matches) {
        [void]$findings.Add([PSCustomObject]@{
          Scope = 'working-tree'
          Rule = $pattern.Name
          Path = $file.FullName.Substring($root.Length + 1)
          Line = $_.LineNumber
          Match = $match.Value
        })
      }
    }
  }
}

if ($IncludeHistory) {
  $commits = git -C $root rev-list --all
  $historyPatterns = @(
    @{ Name = 'private-key'; Regex = 'BEGIN [A-Z ]*PRIVATE KEY' },
    @{ Name = 'generic-secret-assignment'; Regex = 'api[_-]?key|secret|password|client[_-]?secret|access[_-]?token' },
    @{ Name = 'bearer-token'; Regex = 'bearer[[:space:]]+[A-Za-z0-9._-]{16,}' },
    @{ Name = 'ipv4-address'; Regex = '([0-9]{1,3}[.]){3}[0-9]{1,3}' },
    @{ Name = 'public-url'; Regex = 'https?://[^[:space:]]+' },
    @{ Name = 'project-identifier'; Regex = 'astraeus[.]smartdolphin|smartdolphinvpn|smartdolphin' }
  )
  foreach ($commit in $commits) {
    foreach ($pattern in $historyPatterns) {
      git -C $root grep -n -I -i -E $pattern.Regex $commit -- ':!*.lock' 2>$null | ForEach-Object {
        $parts = $_ -split ':', 4
        if ($parts.Count -eq 4) {
          [void]$findings.Add([PSCustomObject]@{
            Scope = "history:$commit"
            Rule = $pattern.Name
            Path = $parts[1]
            Line = $parts[2]
            Match = $parts[3]
          })
        }
      }
    }
  }
}

$findings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $report -Encoding utf8
Write-Host "Audit report: $report"
Write-Host "Findings: $(@($findings).Count)"
