# AZS Save Editor

This is a save editor for **Azeroth Survivors**, a fan-made, survivors-style game set in vanilla WoW. It uses Godot 4.7 with the Compatibility renderer and is written in GDScript.

**Latest tested game version: 0.100.1**, Windows and Linux builds. The top bar shows the version of the game you chose.

Since 0.98.0 the game keeps three talent specs per class (`spec|` save lines). The editor reads and edits all three, and can switch which one is lit, keeping the class's `talent|` line in step as the game does.

You need your own copy of the game. The editor works with either build of the game:
- **Windows:** `AzerothSurvivors.exe`;
- **Linux:** the `AzerothSurvivors` executable.

Saves are the same on both, so you can edit a save from either build with either one. The editor runs on Windows, macOS and Linux, whichever build of the game you have.

The editor reads the save key, the game version and the game data (classes, spells, talents, codex, achievements) from the game executable, and icons from the `Data/patch.MPQ` next to it, at run time. Nothing from the game is bundled. After a game update, new spells, talents and codex entries show up as soon as you point the editor at the new executable, as long as the update keeps the game's table layouts. If it doesn't, loading the game files fails with a message naming the table it couldn't find.

This is an unofficial tool for your own single-player saves. It bypasses the game's tamper check, so please don't share edited saves without the game developer's OK.

## Usage

1. Run the editor, click **Game files…** and select the game executable: `AzerothSurvivors.exe` (Windows build) or `AzerothSurvivors` (Linux build). The `Data` folder next to it is used for icons. Reading the game takes a second or two.
2. **Open save…** loads a `.sav` exported from the game (Options → Export Save).
3. Edit in the tabs, or use **Fill 100%** to unlock everything:
   - **Overview:** heroes and lifetime stats;
   - **Zones:** zones open and won per class;
   - **Talents:** talent XP and ranks, for each of a class's three specs. The lit spec, shown in gold, is the one runs play with; **Make lit** switches to the shown spec as the game does, relearning its ranks within the points earned. Talents that exclude each other, such as the druid's Dire Bear Form and Cat Form, are never learned together;
   - **Collection:** gear per class and tier;
   - **Codex:** rings, trinkets, amulets and legendary amulets;
   - **Achievements.**
4. **Save as…** writes a new sealed save. Overwriting a file keeps a `.bak` copy. Import the result in the game; the game keeps your previous save as a backup when importing.

Lines the editor doesn't understand, such as equipped gear, looks, perks and tabards, are kept unchanged.

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

The save key is HMAC's inner-pad block. Windows keeps it in one piece; Linux keeps it as four 16-byte constants, which `KeyFinder` collects from the `movaps` loads that follow the first one. If a game update changes a row layout, adjust the row sizes and field offsets at the top of the extractor.

Tests (macOS: `godot` = `/Applications/Godot.app/Contents/MacOS/Godot`):

```sh
godot --headless --import          # once, or after adding scripts with class_name
godot --headless --script tests/run_tests.gd
```

Some tests need the real game files and only run when these are set:
- `AZS_EXE=/path/to/AzerothSurvivors.exe` or `/path/to/AzerothSurvivors` (Linux build): game data extracted from the real game, and sample-save tests with the real key. Run the suite once per build;
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
