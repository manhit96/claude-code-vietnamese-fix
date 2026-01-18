# Changelog

## [1.2.0] - 2026-01-18

### Added
- Support for Claude Code v2.1.12

### Fixed
- Fixed `LastIndexOf` logic that was finding wrong `if(` block in newer Claude Code versions
- Fixed regex patterns to handle variable names containing `$` character (e.g., `$A`, `$B`)
- Fixed insert pattern construction with extra backslashes causing match failures

### Technical Details
The patch script had three bugs that prevented it from working with Claude Code v2.1.12:

1. **Wrong block detection**: The `LastIndexOf('if(', startIndex, count)` call was using incorrect parameters, causing it to find a different `if(` block earlier in the code instead of the target block containing the Vietnamese IME bug.

2. **Variable name matching**: Claude Code v2.1.12 uses minified variable names like `$A` which contain the `$` character. The original regex `\w+` doesn't match `$`, so patterns were updated to use `[\$\w]+`.

3. **Pattern escaping**: The insert pattern was constructed with literal backslashes (`"$func\($var\.offset\)\}"`), then escaped again with `[regex]::Escape()`, resulting in double-escaped patterns that couldn't match.

## [1.1.0] - Previous

### Added
- Support for Claude Code v2.1.6 to v2.1.9
- Windows PowerShell script
- macOS bash script
- Binary patching support for macOS (experimental)
