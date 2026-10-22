# Daily Helper rules

Each rule has a severity, an optional fix and a list of cases that it skips on purpose.
A fix marked **check first** starts unticked in the Apply prompt.

Severity sets the score. Each kind of problem costs once (Error 12, Warning 4, Info 1), and many hits
of the same kind cost a little more. One old habit in 200 lines does not drop the score to zero.

## UI and layout

| Rule | Severity | Fix |
|---|---|---|
| ScreenGui uses `Global` ZIndex | Warning | Set `ZIndexBehavior` to `Sibling` |
| `Instance.new("ScreenGui")` in a script that never sets `ZIndexBehavior` | Warning | Add `name.ZIndexBehavior = Enum.ZIndexBehavior.Sibling` after the line |
| `TextScaled` with no `UITextSizeConstraint` (one finding for the whole scope) | Info | None |
| Window of 300 × 300 pixels or more with a fixed size and no `UIScale` | Info | None |
| `player.Name` or `plr.Name` in a `Text =` line | Info | `.Name` → `.DisplayName` (check first) |

A new ScreenGui starts as `Global`. Then a frame with a higher ZIndex draws over the children of a
frame with a lower ZIndex, so a copied window can hide its own list.

## Place tree

| Rule | Severity | Fix |
|---|---|---|
| Two or more siblings with the same name (folders, scripts, remotes, values, GUIs) | Warning | Remove the empty extra folders, but only when no script names them |
| Empty folders with no attributes and no tags | Info | Remove them (check first) |

Skipped:
- A folder that any script names, in code or in a string. A script can fill it or wait for it.
  These folders get one Info line: "named in scripts, kept".
- Parts and models with the same name. Maps often reuse names on purpose.

## Scripts

### Used before its local line (Error)

A top-level `local` name that a line above it uses. Above the `local` line, Luau reads a global of
the same name, which is `nil`.

Fix (check first): a forward declaration. It adds `local Name` at the top of the block that first
uses the name, and it changes `local Name = value` to `Name = value`.

Skipped:
- Type names: lines in `type` and `export type` declarations, names after `:`, `::` and `->`.
- Fields (`a.Name`, `a:Name()`) and table keys (`{ Name = 1 }`).
- Built-in names (`game`, `workspace`, `task` and others).
- Names that also have an inner `local`, a parameter or a loop variable anywhere in the script.
- Declarations with several names or a type annotation get no automatic fix.

### Deprecated globals (Warning)

| Old | New | Note |
|---|---|---|
| `wait()` | `task.wait()` | `task.wait` returns one value, not two |
| `delay()` | `task.delay()` | The callback no longer gets the old timing values |
| `spawn()` | `task.spawn()` | Check first. `task.spawn` runs at once, and `spawn` waited a frame |

Skipped: a script that defines its own `wait`, `delay` or `spawn`.

### Old datatype names (Warning)

Studio's Script Analysis marks these in orange. The API dump lists classes only, so the plugin
keeps a fixed list. Roblox renamed these names years ago and keeps the old names working.

| Old | New | Condition |
|---|---|---|
| `.p`, `.lookVector`, `.rightVector`, `.upVector` | `.Position`, `.LookVector`, `.RightVector`, `.UpVector` | Only after a CFrame-like name: `CFrame`, `cf`, `CoordinateFrame`, `Focus`, `C0`, `C1`, `GetPivot()` |
| `.unit`, `.magnitude` | `.Unit`, `.Magnitude` | Not a call, and no script assigns or defines that field |
| `:inverse()`, `:lerp()`, `:toWorldSpace()`, `:toObjectSpace()`, `:pointToWorldSpace()`, `:pointToObjectSpace()`, `:vectorToWorldSpace()`, `:vectorToObjectSpace()`, `:components()`, `:toEulerAnglesXYZ()`, `:toAxisAngle()` | The same name with a capital letter (`:components()` → `:GetComponents()`) | No script defines a method of that name |
| `CFrame.new(position, lookAt)` | `CFrame.lookAt(position, lookAt)` | Exactly two values in the brackets |

Skipped: `vector.magnitude(v)` (the Luau vector library), `utility.lerp(a, b, t)`, `CFrame.new(v)`,
and game tables such as `config.unit`.

### More than one ProcessReceipt (Error)

`MarketplaceService` keeps only the last `ProcessReceipt`. Purchases that the other scripts handle are
lost. No fix: keep one `ProcessReceipt` and route each product from it.

## Security

These rules never change a script. The developer reads the script and decides.

| Rule | Severity |
|---|---|
| `require(<number>)`: loads a module from the web by its id | Error |
| `require(tonumber(...))`: builds an id at run time to hide it | Error |
| `getfenv` or `setfenv` | Warning |
| `loadstring` | Warning |
| 40 or more escaped characters such as `\104\116` | Warning |
| A Discord webhook address in a string | Warning |

## Performance

| Rule | Severity | Fix |
|---|---|---|
| More than 25,000 parts in Workspace | Warning | None |
| More than 150 unanchored assemblies (no Humanoid) | Warning | None |
| More than 8 enabled lights with shadows | Warning | Turn shadows off (check first) |
| Particle emitters above 200 particles per second | Info | None |
| More than 12 looping sounds that play at start | Info | None |
| Unions with `PreciseConvexDecomposition` | Info | None |

## Live API

At each scan, the plugin reads the API dump for the current Studio build from `setup.rbxcdn.com`.
It keeps a small list of deprecated names in the plugin settings, and it downloads the dump again only
when Roblox ships a new Studio version.

| Rule | Severity | Fix |
|---|---|---|
| A member name that the dump marks deprecated on every class that has it | Warning | Case-only renames, for example `:connect()` → `:Connect()` |
| `Instance.new("<deprecated class>")` | Warning | None |
| Objects of a deprecated class in the tree (one finding per class) | Info | None |

Skipped:
- Names that the game code defines itself (functions, `self.` fields, table keys).
- Lower-case names after a dot, except a short list of classic Roblox names (`className`,
  `userId`, `localPlayer` and others).
- Enum items such as `Enum.KeyCode.Insert`.

## Scope

- **Whole place** reads Workspace, ReplicatedFirst, ReplicatedStorage, ServerScriptService,
  ServerStorage, StarterGui, StarterPack, StarterPlayer, Lighting, SoundService, Teams and
  TextChatService.
- **Selection** reads only the selected objects and their descendants.
- Wally package folders (`_Index`) are skipped.
