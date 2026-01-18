#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code Vietnamese IME Fix - Windows
    Fix loi go tieng Viet trong Claude Code CLI

.DESCRIPTION
    Script nay patch file cli.js cua Claude Code de fix loi:
    - Bo go tieng Viet (EVKey, Unikey, OpenKey...) gui ky tu DEL (0x7F)
    - Claude Code xu ly backspace nhung khong insert text thay the

.PARAMETER Action
    patch   - Ap dung patch (default)
    restore - Khoi phuc ban goc tu backup
    status  - Kiem tra trang thai patch

.EXAMPLE
    .\patch-claude-code-vn-windows.ps1
    .\patch-claude-code-vn-windows.ps1 patch
    .\patch-claude-code-vn-windows.ps1 restore
    .\patch-claude-code-vn-windows.ps1 status

.LINK
    https://github.com/manhit96/claude-code-vietnamese-fix
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('patch', 'restore', 'status', 'fix', 'apply', 'unpatch', 'remove', 'check')]
    [string]$Action = 'patch'
)

$ErrorActionPreference = 'Stop'

# Patch marker
$script:PATCH_MARKER = "/* Vietnamese IME fix */"

# Colors
$script:Colors = @{
    Red    = 'Red'
    Green  = 'Green'
    Yellow = 'Yellow'
    Blue   = 'Cyan'
    White  = 'White'
}

function Write-ColorText {
    param([string]$Text, [string]$Color = 'White')
    Write-Host $Text -ForegroundColor $Color -NoNewline
}

function Write-ColorLine {
    param([string]$Text, [string]$Color = 'White')
    Write-Host $Text -ForegroundColor $Color
}

function Write-Header {
    Write-ColorLine "" $Colors.Blue
    Write-ColorLine ([char]0x2554 + ([string][char]0x2550 * 60) + [char]0x2557) $Colors.Blue
    Write-ColorLine ([char]0x2551 + "     Claude Code Vietnamese IME Fix - Patch Script          " + [char]0x2551) $Colors.Blue
    Write-ColorLine ([char]0x2551 + "     Fix loi go tieng Viet trong Claude Code CLI            " + [char]0x2551) $Colors.Blue
    Write-ColorLine ([char]0x255A + ([string][char]0x2550 * 60) + [char]0x255D) $Colors.Blue
    Write-Host ""
}

function Find-ClaudeCliJs {
    $cliPath = $null

    # Method 1: From claude command
    $claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
    if ($claudeCmd) {
        $claudePath = $claudeCmd.Source

        # Check if binary (can't patch)
        if ($claudePath -match '\.exe$') {
            $fileInfo = Get-Item $claudePath -ErrorAction SilentlyContinue
            if ($fileInfo.Length -gt 1MB) {
                Write-ColorLine "X Claude Code duoc cai bang binary (MSI/Installer)." $Colors.Red
                Write-ColorLine "  Khong the patch ban binary. Vui long cai lai bang npm:" $Colors.Yellow
                Write-Host ""
                Write-ColorLine "  # Go ban cu" $Colors.Green
                Write-Host "  (Go thu cong hoac dung Windows Settings)"
                Write-Host ""
                Write-ColorLine "  # Cai ban npm" $Colors.Green
                Write-Host "  npm install -g @anthropic-ai/claude-code"
                Write-Host ""
                return $null
            }
        }

        # npm install - find cli.js
        if ($claudePath -match '\.(cmd|bat|ps1)$') {
            $claudeDir = Split-Path $claudePath -Parent
            $npmModules = Join-Path $claudeDir "node_modules\@anthropic-ai\claude-code\cli.js"
            if (Test-Path $npmModules) {
                return $npmModules
            }
        }
    }

    # Method 2: npm root -g
    try {
        $npmRoot = & npm root -g 2>$null
        if ($npmRoot) {
            $cliPath = Join-Path $npmRoot "@anthropic-ai\claude-code\cli.js"
            if (Test-Path $cliPath) {
                return $cliPath
            }
        }
    }
    catch { }

    # Method 3: Common paths
    $commonPaths = @(
        "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code\cli.js"
        "$env:USERPROFILE\AppData\Local\npm\node_modules\@anthropic-ai\claude-code\cli.js"
    )

    # nvm-windows
    $nvmRoot = $env:NVM_HOME
    if ($nvmRoot -and (Test-Path $nvmRoot)) {
        Get-ChildItem $nvmRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^v?\d+' } | ForEach-Object {
            $commonPaths += Join-Path $_.FullName "node_modules\@anthropic-ai\claude-code\cli.js"
        }
    }

    # fnm
    $fnmRoot = "$env:USERPROFILE\.fnm\node-versions"
    if (Test-Path $fnmRoot) {
        Get-ChildItem $fnmRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $commonPaths += Join-Path $_.FullName "installation\lib\node_modules\@anthropic-ai\claude-code\cli.js"
        }
    }

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    return $null
}

function Test-IsPatched {
    param([string]$CliPath)

    if (-not (Test-Path $CliPath)) {
        return $false
    }

    $content = Get-Content $CliPath -Raw -ErrorAction SilentlyContinue
    return $content -match [regex]::Escape($PATCH_MARKER)
}

function Get-ClaudeVersion {
    try {
        $version = & claude --version 2>$null | Select-Object -First 1
        return $version
    }
    catch {
        return "unknown"
    }
}

function Invoke-Patch {
    param([string]$CliPath)

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = "$CliPath.backup-$timestamp"

    Write-ColorLine "-> Dang tao backup..." $Colors.Yellow
    Copy-Item $CliPath $backupPath -Force
    Write-Host "   Backup: $backupPath"

    Write-ColorLine "-> Dang phan tich va ap dung patch..." $Colors.Yellow

    # Read file content
    $content = Get-Content $CliPath -Raw -Encoding UTF8

    # Check if already patched
    if ($content -match [regex]::Escape($PATCH_MARKER)) {
        Write-ColorLine "   Da patch truoc do." $Colors.Green
        return $true
    }

    # Dynamic variable extraction approach
    # Find the bug block by looking for .includes("\x7f") with actual DEL character
    $DEL_CHAR = [char]0x7F

    # Find the includes check with DEL character
    $includesPattern = ".includes(`"$DEL_CHAR`")"
    $idx = $content.IndexOf($includesPattern)

    if ($idx -eq -1) {
        Write-ColorLine "   Khong tim thay pattern can patch." $Colors.Red
        Write-Host "   Code structure co the da thay doi trong phien ban moi."
        return $false
    }

    # Find the full if block containing this pattern
    # Search for 'if(' in the 150 chars before the .includes pattern
    $searchStart = [Math]::Max(0, $idx - 150)
    $searchRange = $content.Substring($searchStart, $idx - $searchStart)
    $ifOffset = $searchRange.LastIndexOf('if(')
    if ($ifOffset -eq -1) {
        Write-ColorLine "   Khong tim thay block if." $Colors.Red
        return $false
    }
    $blockStart = $searchStart + $ifOffset

    # Find matching closing brace
    $depth = 0
    $blockEnd = $idx
    for ($i = 0; $i -lt 800 -and ($blockStart + $i) -lt $content.Length; $i++) {
        $c = $content[$blockStart + $i]
        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) {
                $blockEnd = $blockStart + $i + 1
                break
            }
        }
    }

    $fullBlock = $content.Substring($blockStart, $blockEnd - $blockStart)
    $fullBlockEscaped = $fullBlock.Replace([string]$DEL_CHAR, '\x7f')

    # Extract variable names dynamically using regex
    # Pattern: let COUNT=(INPUT.match(/\x7f/g)||[]).length,STATE=CURSTATE;
    # Note: Variable names may contain $ (e.g., $A), so use [\$\w]+ instead of \w+
    $patched = $false

    if ($fullBlockEscaped -match 'let ([\$\w]+)=\(([\$\w]+)\.match\(/\\x7f/g\)\|\|\[\]\)\.length,([\$\w]+)=([\$\w]+);') {
        $countVar = $Matches[1]
        $inputVar = $Matches[2]
        $stateVar = $Matches[3]
        $curStateVar = $Matches[4]

        # Extract update functions: UPDATETEXT(STATE.text);UPDATEOFFSET(STATE.offset)
        if ($fullBlock -match "([\$\w]+)\($stateVar\.text\);([\$\w]+)\($stateVar\.offset\)") {
            $updateTextFunc = $Matches[1]
            $updateOffsetFunc = $Matches[2]

            # Find insertion point: right after UPDATEOFFSET(STATE.offset)}
            # Build literal string first, then escape for regex
            $insertPattern = "$updateOffsetFunc($stateVar.offset)}"
            $insertMatch = [regex]::Match($fullBlock, [regex]::Escape($insertPattern))

            if ($insertMatch.Success) {
                # Calculate absolute position for insertion
                $relativePos = $insertMatch.Index + $insertMatch.Length
                $absolutePos = $blockStart + $relativePos

                # Build fix code with extracted variable names
                $fixCode = $PATCH_MARKER + "let _vn=$inputVar.replace(/\x7f/g,`"`");if(_vn.length>0){for(const _c of _vn)$stateVar=$stateVar.insert(_c);if(!$curStateVar.equals($stateVar)){if($curStateVar.text!==$stateVar.text)$updateTextFunc($stateVar.text);$updateOffsetFunc($stateVar.offset)}}"

                # Insert fix code
                $content = $content.Substring(0, $absolutePos) + $fixCode + $content.Substring($absolutePos)
                $patched = $true
                Write-Host "   Tim thay: input=$inputVar, state=$stateVar, cur=$curStateVar"
            }
        }
    }

    if ($patched) {
        # Write back with UTF8 encoding (no BOM for compatibility)
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($CliPath, $content, $utf8NoBom)

        # Verify patch
        $verifyContent = Get-Content $CliPath -Raw -ErrorAction SilentlyContinue
        if ($verifyContent -match [regex]::Escape($PATCH_MARKER)) {
            return $true
        }
        else {
            # Restore backup
            Write-ColorLine "-> Patch that bai, dang khoi phuc..." $Colors.Yellow
            Copy-Item $backupPath $CliPath -Force
            return $false
        }
    }
    else {
        Write-ColorLine "   Khong tim thay pattern can patch." $Colors.Red
        Write-Host "   Code structure co the da thay doi trong phien ban moi."
        return $false
    }
}

function Invoke-Restore {
    param([string]$CliPath)

    $cliDir = Split-Path $CliPath -Parent
    $backups = Get-ChildItem $cliDir -Filter "cli.js.backup-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    if (-not $backups -or $backups.Count -eq 0) {
        Write-ColorLine "X Khong tim thay file backup." $Colors.Red
        Write-Host "  Ban co the cai lai Claude Code de khoi phuc:"
        Write-ColorLine "  npm install -g @anthropic-ai/claude-code" $Colors.Green
        return $false
    }

    $latestBackup = $backups[0]

    Write-ColorLine "-> Dang khoi phuc tu backup..." $Colors.Yellow
    Write-Host "   Backup: $($latestBackup.FullName)"

    Copy-Item $latestBackup.FullName $CliPath -Force
    Remove-Item $latestBackup.FullName -Force

    Write-ColorLine "OK Da khoi phuc Claude Code ve ban goc." $Colors.Green
    return $true
}

function Show-Status {
    param([string]$CliPath)

    Write-ColorLine "-> Kiem tra trang thai patch..." $Colors.Yellow
    Write-Host ""

    if (Test-IsPatched $CliPath) {
        Write-ColorText "   Trang thai: " $Colors.White
        Write-ColorLine "OK Da patch" $Colors.Green
    }
    else {
        Write-ColorText "   Trang thai: " $Colors.White
        Write-ColorLine "X Chua patch" $Colors.Red

        # Check if bug code exists
        $content = Get-Content $CliPath -Raw -ErrorAction SilentlyContinue
        $hasBugCode = ($content -match 'backspace\(\)') -and ($content -match '\\x7f|"\x7f"')

        if ($hasBugCode) {
            Write-ColorLine "   Bug code:   Co ton tai - Can patch!" $Colors.Yellow
        }
        else {
            Write-ColorLine "   Bug code:   Khong tim thay - Co the da fix boi Anthropic" $Colors.Blue
        }
    }

    # Show backups
    $cliDir = Split-Path $CliPath -Parent
    $backups = Get-ChildItem $cliDir -Filter "cli.js.backup-*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    if ($backups) {
        Write-Host "   Backup:     $($backups.Count) file(s)"
    }
}

# Main
function Main {
    Write-Header

    Write-ColorLine "-> Dang tim Claude Code..." $Colors.Yellow

    $cliPath = Find-ClaudeCliJs

    if (-not $cliPath -or -not (Test-Path $cliPath)) {
        Write-ColorLine "X Khong tim thay Claude Code." $Colors.Red
        Write-Host "  Vui long cai dat Claude Code truoc:"
        Write-ColorLine "  npm install -g @anthropic-ai/claude-code" $Colors.Green
        return
    }

    Write-ColorLine "   Duong dan: $cliPath" $Colors.Blue
    Write-ColorLine "   Phien ban: $(Get-ClaudeVersion)" $Colors.Blue
    Write-Host ""

    # Normalize action
    switch ($Action) {
        { $_ -in 'patch', 'fix', 'apply' } {
            if (Test-IsPatched $cliPath) {
                Write-ColorLine "OK Claude Code da duoc patch truoc do." $Colors.Green
                return
            }

            Write-ColorLine "-> Dang ap dung patch..." $Colors.Yellow

            if (Invoke-Patch $cliPath) {
                Write-Host ""
                Write-ColorLine ([char]0x2554 + ([string][char]0x2550 * 60) + [char]0x2557) $Colors.Green
                Write-ColorLine ([char]0x2551 + "  OK Patch thanh cong! Vietnamese IME fix da duoc ap dung.  " + [char]0x2551) $Colors.Green
                Write-ColorLine ([char]0x255A + ([string][char]0x2550 * 60) + [char]0x255D) $Colors.Green
                Write-Host ""
                Write-ColorText "Vui long " $Colors.White
                Write-ColorText "khoi dong lai Claude Code" $Colors.Yellow
                Write-Host " de ap dung thay doi."
                Write-Host ""
            }
            else {
                Write-Host ""
                Write-ColorLine "X Khong the ap dung patch." $Colors.Red
                Write-Host "  Code structure co the da thay doi trong phien ban moi."
                Write-Host "  Vui long bao loi tai: https://github.com/manhit96/claude-code-vietnamese-fix/issues"
                return
            }
        }

        { $_ -in 'restore', 'unpatch', 'remove' } {
            if (-not (Test-IsPatched $cliPath)) {
                Write-ColorLine "Claude Code chua duoc patch." $Colors.Yellow
                return
            }

            if (Invoke-Restore $cliPath) {
                Write-ColorLine "OK Da go patch thanh cong." $Colors.Green
            }
            else {
                return
            }
        }

        { $_ -in 'status', 'check' } {
            Show-Status $cliPath
        }
    }

}

Main

# Pause at end so user can see results
Write-Host ""
Write-Host "Nhan phim bat ky de dong cua so nay..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
