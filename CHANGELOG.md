# Changelog

Every push adds a dated entry below. The newest entry is at the top.

## 2026-10-22: Releases page and beta notice

**What:** the first GitHub release, `v0.2.0-beta`, with `DailyHelper.rbxm` and `DailyHelper.rbxmx` as
direct downloads.

**Where:** `README.md` (download links to the latest release, a beta notice, update steps) and this
file. The release itself is on the Releases page.

**Why:** visitors can download the plugin in one click, with no need to open the `dist/` folder. The
beta notice tells them that the plugin gets regular updates and that each update comes as a new
release. The links use `releases/latest`, so they always point to the newest version.

## 2026-10-22: v0.2.0, first public push

**What:** the first release of Daily Helper, a Roblox Studio plugin that audits the open place.

**Where:**
- `src/`: the plugin source (Luau). `init.server.luau` makes the toolbar button and the dock
  window. `App.luau`, `View.luau` and `Theme.luau` hold the state and the UI. `Scanner.luau`,
  `Lexer.luau`, `Edit.luau` and `ApiDump.luau` hold the audit engine. `Checks/` holds the rules.
- `dist/DailyHelper.rbxm` and `dist/DailyHelper.rbxmx`: the built plugin, ready for the Plugins
  folder. Both files hold the same 18 scripts.
- `build.py`: packs `src/` into `dist/DailyHelper.rbxmx` and installs it.
- `docs/CHECKS.md`: every rule, its fix and what it skips. `docs/images/`: screenshots, the icon
  and the design mockup.

**Why:** a daily check that every developer can run in a few seconds, with no change to the place
unless the developer asks for it.

**Features:**
- Six checks: UI and layout, Place tree, Scripts, Security, Performance and Live API.
- Live API: reads the Roblox API dump of the current Studio build at each scan.
- Script rules: a name used above its `local` line, `wait`/`delay`/`spawn`, old CFrame and Vector3
  names, more than one `ProcessReceipt`.
- Fixes: an Apply prompt after the scan, risky fixes unticked, a before and after preview on each
  script fix, a Restore button, a text check before each edit.
- Findings tab with a search bar and severity filters. A Log tab per place.
- Start screen and Information screen. Neo-Brutalism theme with Montserrat text. Text size setting
  (100% to 175%), because Studio does not scale plugin windows.

**Tested:** a full scan of a place with 94,731 instances and 332 scripts in about 5 seconds. Each rule
and each fix path (one line, many lines, copies in many scripts, a forward declaration, Restore) on
test scripts. A second place gave no false alarms for the declaration rule.

**Known limits:** see the Limits section of the README. The toolbar icon shows after its Creator Store
listing passes review.
