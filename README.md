# AZS Save Editor

This is a save editor for **Azeroth Survivors**, a fan-made, survivors-style game set in vanilla WoW. It uses Godot 4.7 with the Compatibility renderer and is written in GDScript.

**Latest tested game version: 0.94.0.** After a game update, regenerate `data/azs-data.json` from the new exe (see Development) so new spells, talents and codex entries show up.

You need your own copy of the game. The editor reads the save key and the game data from your `AzerothSurvivors.exe`, and icons from your `Data/patch.MPQ`, at run time. Nothing from the game is bundled.

This is an unofficial tool for your own single-player saves. It bypasses the game's tamper check, so please don't share edited saves without the game developer's OK.

## Usage

1. Generate `data/azs-data.json` once (see Development).
2. Run the project, click **Game files…** and select your `AzerothSurvivors.exe`. The `Data` folder next to it is used for icons.
3. **Open save…** loads a `.sav` exported from the game (Options → Export Save).
4. Edit in the tabs, or use **Fill 100%** to unlock everything:
   - **Overview:** heroes and lifetime stats;
   - **Zones:** zones open and won per class;
   - **Talents:** talent XP and ranks. Talents that exclude each other, such as the druid's Dire Bear Form and Cat Form, are never learned together;
   - **Collection:** gear per class and tier;
   - **Codex:** rings, trinkets, amulets and legendary amulets;
   - **Achievements.**
5. **Save as…** writes a new sealed save. Overwriting a file keeps a `.bak` copy. Import the result in the game; the game keeps your previous save as a backup when importing.

Lines the editor doesn't understand, such as equipped gear, looks, perks and tabards, are kept unchanged.

## Building

Exports need the Godot 4.7.2 export templates. Generate `data/azs-data.json` first: the presets bundle it into the build (personal builds only; it's data derived from the game).

```sh
godot --headless --export-release "macOS" "build/macos/AZS Save Editor.zip"
godot --headless --export-release "Windows Desktop" "build/windows/AZS Save Editor.exe"
godot --headless --export-release "Linux" "build/linux/azs-save-editor.x86_64"
```

- **macOS:** a universal app with an ad-hoc signature. On another Mac, open it the first time via right-click → Open.
- **Windows and Linux:** x86_64 single-file executables with the data packed in.
- **Output:** builds go to the gitignored `build/` folder. `tests/` and `tools/` are excluded from exports.

## Development

The editor reads game data from `data/azs-data.json`. That file is generated from your own exe by the extractor in the Azeroth Survivors knowledge base (`tools/azs-data`):

```sh
python3 tools/azs-data/extract.py /path/to/AzerothSurvivors.exe /path/to/azs-save-editor/data/azs-data.json
```

Tests (macOS: `godot` = `/Applications/Godot.app/Contents/MacOS/Godot`):

```sh
godot --headless --import          # once, or after adding scripts with class_name
godot --headless --script tests/run_tests.gd
```

Some tests need the real game files and only run when these are set:
- `AZS_EXE=/path/to/AzerothSurvivors.exe`: sample-save tests with the real key;
- `AZS_DATA=/path/to/Data`: MPQ and icon tests.

To check icon decoding by eye, render every icon the game data references into one sheet:

```sh
godot --headless --script tools/render_icon_sheet.gd -- /path/to/Data icons.png
```

To review the UI, take a screenshot of every tab with a save loaded. This needs a display, so don't pass `--headless`:

```sh
godot --script tools/capture_screens.gd -- /path/to/AzerothSurvivors.exe tests/fixtures/sample.sav screens/
```

### Conventions

- **No game data in the repo.** Don't commit the save key, MPQ contents, data derived from the exe, or saves other than the test fixture. Generated data goes into the gitignored `data/` folder.
- **Layout:**
  - Pure logic (`src/codec`, `src/model`, `src/assets` parsers) has no scene or UI dependencies and is unit-tested.
  - `src/ui` only wires things together.
  - Fallible operations return a `Result` (`src/core/result.gd`).
- **Tests:** add tests alongside logic changes. Scene wiring and rendering aren't unit-tested.
- **Style:** static typing everywhere, `class_name` for reusable scripts, and tabs for indentation per the Godot style guide.
- **Commits:** use scoped conventional commits, `type(scope): summary`, e.g. `feat(codec): add RSE1 seal`. Make one logical change per commit.
