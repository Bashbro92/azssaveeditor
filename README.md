# AZS Save Editor

This is a save editor for **Azeroth Survivors**, a fan-made, survivors-style game set in vanilla WoW. It uses Godot 4.7 with the Compatibility renderer and is written in GDScript.

**Latest tested game version: 0.103.1**, Windows and Linux builds. The top bar shows the version of the game you chose.

Since 0.98.0 the game keeps three talent specs per class (`spec|` save lines). The editor reads and edits all three, and can switch which one is lit, keeping the class's `talent|` line in step as the game does. No save line changed from 0.100.1 to 0.103.1. From 0.102.3 the game opens the zone after each won one when it reads a save, and the editor does the same. 0.103.1 adds the no u achievement (73 in all) and the Sapphiron companion look it unlocks; both show up in the editor.

You need your own copy of the game. The editor works with either build of the game:
- **Windows:** `AzerothSurvivors.exe`;
- **Linux:** the `AzerothSurvivors` executable.

Saves are the same on both, so you can edit a save from either build with either one. The editor runs on Windows, macOS and Linux, whichever build of the game you have.

The editor reads the save key, the game version and the game data (classes, spells, talents, codex, achievements, perks, tabards, companions) from the game executable, and icons from the `Data/patch.MPQ` next to it, at run time. Nothing from the game is bundled. After a game update, new spells, talents and codex entries show up as soon as you point the editor at the new executable, as long as the update keeps the game's table layouts. If it doesn't, loading the game files fails with a message naming the table it couldn't find.

This is an unofficial tool for your own single-player saves. It bypasses the game's tamper check, so please don't share edited saves without the game developer's OK.

## Usage

1. Run the editor, click **Game files…** and select the game executable: `AzerothSurvivors.exe` (Windows build) or `AzerothSurvivors` (Linux build). The `Data` folder next to it is used for icons. Reading the game takes a second or two.
2. **Open save…** loads a `.sav` exported from the game (Options → Saves → Export Save), one of the game's hourly backups, or the game's own `characters.txt` (see [Where the game keeps its save](#where-the-game-keeps-its-save)).
3. Edit in the tabs, or use **Fill 100%** to unlock everything:
   - **Overview:** heroes and lifetime stats;
   - **Zones:** zones open and won per class;
   - **Talents:** talent XP and ranks, for each of a class's three specs. The lit spec, shown in gold, is the one runs play with; **Make lit** switches to the shown spec as the game does, relearning its ranks within the points earned. Talents that exclude each other, such as the druid's Dire Bear Form and Cat Form, are never learned together;
   - **Collection:** gear per class and tier;
   - **Codex:** rings, trinkets, amulets and legendary amulets;
   - **Achievements;**
   - **Perks:** perk ranks and resets, tabards bought with perk points, and the two companions' looks.
4. **Save as…** writes a sealed save, named as the game names its exports (`AzerothSurvivors YYYY-MM-DD HH-MM-SS.sav`, UTC) and placed in the game's `Saves` folder when it has one. Overwriting a file keeps a `.bak` copy.
5. In the game, import it with **Options → Saves → Import Save**. The game lists the `.sav` files of its `Saves` folder, and keeps your previous save as `characters.before-import.txt` when importing. Import only takes sealed saves (`RSE1:`), which is what the editor writes.

The editor reads a save as the game reads it and writes it as the game writes it: the same lines in the same order, lists sorted, one `beat` line and one `open` line per class, `stat` only when a count isn't 0, and only dated achievements in `achat`. A save the game wrote comes back byte for byte; an older save (0.94 or 0.95 `unlock` lines, say) comes out as the game would rewrite it. Like the game, the editor opens the zone after each won one (0.102.3 on), drops lines it doesn't know, relearns talents within the points their XP earns, and keeps the last pick, equipped gear and transmog looks as they are. Hero looks aren't checked against what a race offers; the game does that when it loads the save.

## Where the game keeps its save

The game reads and writes `characters.txt` in its data folder, and keeps exports and its hourly backups (`Backup YYYY-MM-DD HH-MM-SS.sav`, the last 5) in `Saves` next to it:

| platform | save | exports and backups |
|---|---|---|
| Windows | `%APPDATA%\wenilla-rogue\characters.txt` | `%APPDATA%\wenilla-rogue\Saves` |
| Linux | `~/.local/share/wenilla-rogue/characters.txt` (or `$XDG_DATA_HOME/wenilla-rogue/`) | `~/.local/share/wenilla-rogue/Saves` |
| macOS (no game build of its own; the same rule) | `~/.local/share/wenilla-rogue/characters.txt` | `~/.local/share/wenilla-rogue/Saves` |
| web (wow.aethus.pl) | the browser's storage | Options → Saves: Export Save downloads a `.sav`, Import Save takes one |

If `WOW_ROGUE_SAVE` is set, the game uses that file instead, with `Saves` in its folder. Prefer importing over replacing `characters.txt`: the game writes `characters.txt` whenever your progress changes, so a running game overwrites it.

## Building

Exports need the Godot 4.7.2 export templates.

```sh
godot --headless --export-release "macOS" "build/macos/AZS Save Editor.zip"
godot --headless --export-release "Windows Desktop" "build/windows/AZS Save Editor.exe"
godot --headless --export-release "Linux" "build/linux/azs-save-editor.x86_64"
```

- **macOS:** a universal app with an ad-hoc signature. On another Mac, open it the first time via right-click → Open.
- **Windows and Linux:** x86_64 single-file executables.
- **Output:** builds go to the gitignored `build/` folder. `tests/` and `tools/` are excluded from exports.

## Development

Game data comes from the game executable through `GameDataExtractor` (`src/model/game_data_extractor.gd`). The game is a Rust program. Its content tables are rows of static values: strings and lists are (pointer, length) pairs. The extractor finds each table by a string in its first row and reads the rows from there. The fixed achievements are read from the code that builds them: each `lea` of a string literal, followed by its length.

`ExeImage` (`src/codec/exe_image.gd`) reads both builds:
- **Windows (PE32+):** pointers are stored in place, in `.rdata`.
- **Linux (ELF64, position-independent):** the pointers in `.data.rel.ro` are zero in the file. Opening the executable fills them in from the `R_X86_64_RELATIVE` relocations, so the extractor reads both builds the same way.

`SaveProgress` (`src/model/save_progress.gd`) is the game's save reader and writer: each line kind has its own pass with the game's field counts and number parsing, and `to_text` writes the lines in the writer's order. `GameSaveLocation` (`src/core/game_save_location.gd`) finds the game's save folder from the environment as the game does.

The save key is HMAC's inner-pad block. Windows keeps it in one piece; Linux keeps it as four 16-byte constants, which `KeyFinder` collects from the `movaps` loads that follow the first one. If a game update changes a row layout, adjust the row sizes and field offsets at the top of the extractor.

Tests (macOS: `godot` = `/Applications/Godot.app/Contents/MacOS/Godot`):

```sh
godot --headless --import          # once, or after adding scripts with class_name
godot --headless --script tests/run_tests.gd
```

Some tests need the real game files and only run when these are set:
- `AZS_EXE=/path/to/AzerothSurvivors.exe` or `/path/to/AzerothSurvivors` (Linux build): game data extracted from the real game, and sample-save tests with the real key. Run the suite once per build;
- `AZS_GAME_SAVE=/path/to/a/copy.sav` (with `AZS_EXE`): a save the game wrote must come back byte for byte. Use a copy, never the game's own file;
- `AZS_DATA=/path/to/Data`: MPQ and icon tests.

To check icon decoding by eye, render every icon the game data references into one sheet:

```sh
godot --headless --script tools/render_icon_sheet.gd -- /path/to/AzerothSurvivors.exe icons.png   # or the Linux executable
```

To review the UI, take a screenshot of every tab with a save loaded. This needs a display, so don't pass `--headless`:

```sh
godot --script tools/capture_screens.gd -- /path/to/AzerothSurvivors.exe tests/fixtures/sample.sav screens/   # or the Linux executable
```

### Conventions

- **No game data in the repo or in builds.** Don't commit the save key, MPQ contents, data derived from the game executable, or saves other than the test fixture. Everything from the game is read at run time from the user's own files. Test fixtures are synthetic.
- **Layout:**
  - Pure logic (`src/codec`, `src/model`, `src/assets` parsers) has no scene or UI dependencies and is unit-tested.
  - `src/ui` only wires things together.
  - Fallible operations return a `Result` (`src/core/result.gd`).
- **Tests:** add tests alongside logic changes. Scene wiring and rendering aren't unit-tested.
- **Style:** static typing everywhere, `class_name` for reusable scripts, and tabs for indentation per the Godot style guide.
- **Commits:** use scoped conventional commits, `type(scope): summary`, e.g. `feat(codec): add RSE1 seal`. Make one logical change per commit.
