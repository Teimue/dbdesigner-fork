
# DBDesigner Fork ![License: GPL v2](https://img.shields.io/badge/License-GPLv2-blue.svg)

**DBDesigner Fork** is an open-source visual database design and modeling tool (Entity-Relationship / EER diagram editor). It is a community fork of the original **DBDesigner 4**, created by fabFORCE (Mike). This repository ports it from Delphi/Kylix to Free Pascal / Lazarus.

![DBDesigner Fork running under Lazarus/GTK2 on Linux](docs/1.jpeg?raw=true)

![DBDesigner Fork running on Windows 11 (German user interface, 150 % display scaling)](docs/2_windows.png?raw=true)

## Overview

DBDesigner Fork provides a full-featured graphical environment for designing and managing relational database schemas. It allows you to visually create Entity-Relationship diagrams and generate SQL scripts, reverse-engineer existing databases, and much more.

## Key Facts

| Aspect | Details |
|---|---|
| **Language** | Object Pascal (Free Pascal / Lazarus LCL) — originally Delphi 7 / CLX |
| **License** | GNU General Public License v2 (GPLv2) |
| **Original** | DBDesigner 4 (v4.0.2.92) by fabFORCE |
| **Fork versions** | Fork 1.0 (Sep 2006) → Fork 1.5 (Oct 2010) → Lazarus port (2026) |
| **Original platforms** | Windows (Delphi 7) and Linux (Kylix 3) |
| **Current platforms** | Linux (Lazarus/FPC, GTK2) and Windows (64 bit, see [Windows Version](#windows-version)) — macOS possible but untested |
| **Databases** | MySQL 8, SQLite 3 and Firebird 3+ (others not ported yet) |
| **Codebase size** | ~150,000 lines of Pascal source code (main app + plugins) |

## Features

- **Visual database modeling** — Design Entity-Relationship (EER) diagrams with tables, fields, relations (1:1, 1:n, n:m), regions, notes, and images.
- **SQL script export** — Generate CREATE TABLE scripts (and drop / optimize / repair scripts) from the visual model.
- **Reverse engineering** — Import existing MySQL or SQLite schemas into visual models, including relations from foreign keys.
- **Database connectivity** — MySQL 8, SQLite 3 and Firebird (server or embedded) through FPC's SQLDB, behind a DBExpress-compatible shim.
- **XML model storage** — Models are saved as XML files; ERwin 4.1 import exists but is untested.
- **Query editor** — Visual SQL query builder with drag-and-drop and a result grid.
- **Synchronization** — Sync models with live MySQL, SQLite and Firebird databases.
- **PDF generation** — Embedded PDF export of diagrams (untested in the port).
- **Plugin system** — Extensible via plugins (HTML Report, Data Importer, Simple Web Front-end, Test Data Generator, Demo).
- **Test data** — The Test Data Generator plugin fills the tables of a model with plausible rows, as a script or directly in a database.
- **Multi-language support** — Translation files for internationalization; the German translation is complete.
- **High DPI** — On Windows the program is DPI aware and scales its dialogs, symbols, cursors and the model with the display.

## Building with Lazarus

**Requirements:**
- Free Pascal Compiler (FPC) 3.2.2+
- Lazarus 3.0+ (for `lazbuild` command-line tool)
- Required Lazarus packages: `LCL`, `SynEdit`

**Build all projects:**
```bash
# Main application
lazbuild DBDesignerFork.lpi

# Plugins
lazbuild Plugins/Demo/DBDplugin_Demo.lpi
lazbuild Plugins/HTMLReport/DBDplugin_HTMLReport.lpi
lazbuild Plugins/DataImporter/DBDplugin_DataImporter.lpi
lazbuild Plugins/SimpleWebFront/DBDplugin_SimpleWebFront.lpi
lazbuild Plugins/TestDataGenerator/DBDplugin_TestDataGenerator.lpi
```

On Windows `lazbuild` is not on the path; call it as `C:\lazarus\lazbuild.exe` (or wherever Lazarus is installed).

All binaries are output to the `bin/` directory (they are not tracked in git). Note that `lazbuild` does not rebuild after a change to a `.lfm` file alone; touch the matching `.pas` file.

| Project | Lines Compiled | Binary |
|---------|---------------|--------|
| Main Application | 56,608 | `bin/DBDesignerFork` |
| Demo Plugin | 21,793 | `bin/DBDplugin_Demo` |
| HTMLReport Plugin | 22,258 | `bin/DBDplugin_HTMLReport` |
| DataImporter Plugin | 8,836 | `bin/DBDplugin_DataImporter` |
| SimpleWebFront Plugin | 40,096 | `bin/DBDplugin_SimpleWebFront` |
| TestDataGenerator Plugin | 25,600 | `bin/DBDplugin_TestDataGenerator` |
| **Total** | **~150,000** | |

**Runtime requirements (Linux):**
- GTK2 libraries
- `libsqlite3.so.0` for SQLite connections
- `libmysqlclient.so.21` (MySQL 8 client library) for MySQL connections

Both libraries are loaded on demand by their versioned name, so no `-dev` package or symlink is needed. Settings, the connection list (`DBConn.ini`) and recent files are stored in `~/.DBDesigner4/`.

**Runtime requirements (Windows, 64 bit):**
- `sqlite3.dll` for SQLite connections
- `libmysql.dll` (MySQL 8 client library, with the OpenSSL / zlib / zstd DLLs it needs) for MySQL connections
- `fbclient.dll` (Firebird 3 or newer) for Firebird connections; the same library is the embedded engine when its other files lie next to it

The 64-bit libraries are looked for next to the program (`bin\`); they are not part of the repository. Settings are stored in `%APPDATA%\DBDesigner4\`.

**Run:**
```bash
./bin/DBDesignerFork                       # empty model
./bin/DBDesignerFork bin/Examples/order.xml
```

## Testing

### Automated UI self-test

An automated **UI Test Runner** ([`src/UITestRunner.pas`](src/UITestRunner.pas)) programmatically clicks every safe menu item and button, catching and reporting unhandled exceptions with stack traces. It is also reachable from the running application via *Database → Run UI Tests*.

```bash
# Exits 0 on success, N on N failures; results in /tmp/UITestResults.log
./bin/DBDesignerFork --selftest
# Headless
xvfb-run -a ./bin/DBDesignerFork --selftest
```

**Current baseline: 93 PASS, 0 FAIL, 78 SKIP.** The skips are the deliberately unsafe items (exit, save, open, print, database operations, browser links), separators, submenu parents and items that are disabled without a model. The self-test never opens a database connection and leaves the user's settings and `DBConn.ini` untouched.

The self-test covers:
- ✅ Application launch and UI rendering
- ✅ All display/notation/style menu items
- ✅ All toolbar speed buttons (29 tool selectors)
- ✅ Palette show/hide/dock/undock operations
- ✅ Window arrangement (cascade, tile)
- ✅ Design/query mode switching
- ✅ New model creation
- ✅ Buttons of every other visible form (options, editors, palettes)

Areas outside the self-test, verified manually on a real display (see the bug catalogs):
- Database connectivity, reverse engineering, synchronisation and Query mode against MySQL 8 and SQLite 3
- Model loading/saving through the UI
- Plugin loading and end-to-end plugin runs
- Table, Relation and Index editors, field editing on a blank model
- Undo/redo, copy/paste within and across models, Place Model from file
- Canvas regions, notes and images; mixed-selection paste and delete/undo; model and selection image export
- Query mode editing on MySQL 8 and SQLite 3: editable result grid with Apply Changes, ISO dates, stored SQL commands
- Start-up tips window (parked in the lower-right corner, off the canvas)

Areas still requiring manual or integration testing:
- PDF export
- Print / page setup output
- ERwin import, Open/Save model in database
- Oracle, MS SQL Server and ODBC (connectors not linked yet)
- The macOS build

### Standalone tests and round-trip scripts

| File | What it checks |
|---|---|
| `tests/TestModelLoad.pas` | XML model parsing without the LCL |
| `tests/TestSQLite.pas` | Direct SQLDB SQLite3 connectivity |
| `tests/TestSQLExprShim.pas` | The `sqlexpr` shim against SQLite: transactions, DML commit, idle lock release |
| `tests/TestMySQLShim.pas` | The shim's MySQL schema queries against a live MySQL 8 server |
| `DBDesignerFork --screenshots <dir>` | Saves a picture of every dialog with every page (`src/UIScreenshots.pas`) to check the layout after a change of fonts, translations or scaling; runs with read-only settings like `--selftest` |
| `tests/TestSQLiteSync.pas` | Database synchronisation against SQLite on the order example: create, ALTER TABLE changes, table rebuild, renamed table (`lazbuild tests/TestSQLiteSync.lpi`) |
| `tests/TestFirebirdSync.pas` | Firebird on the order example, embedded engine or server: create, column / index / primary key / foreign key changes, renamed table, reverse engineering of the result, SQL create script loaded with isql (`lazbuild tests/TestFirebirdSync.lpi`, needs the Firebird client library) |
| `tests/TestTestDataGen.pas` | The test data generator on the order example: the script is executed in a SQLite database created from the model (row counts, foreign keys, column lengths, same seed = same script), execution in one transaction with rollback on an error (`lazbuild tests/TestTestDataGen.lpi`) |
| `tests/sqlite-roundtrip.sh` | Loads an exported SQL script into sqlite3 and prints a schema summary |
| `tests/mysql-roundtrip.sh` | Same for MySQL (drops and recreates the given database) |

The Pascal tests compile with plain `fpc` (see the header of each file). `TestSQLExport.pas` needs the full application infrastructure and is not run standalone.

### Bug catalogs

Runtime testing is done in rounds: one diagnosis pass on a real display writes a catalog, each entry is then fixed and re-verified. The catalogs are the authoritative record of what was tested and what is still open.

| Catalog | Scope | Entries |
|---|---|---|
| [`docs/ui-bug-catalog.md`](docs/ui-bug-catalog.md) | Dialogs, palettes, options, plugins start-up | 22 (19 fixed, 1 partial, 2 not bugs) |
| [`docs/sqlite-bug-catalog.md`](docs/sqlite-bug-catalog.md) | SQLite export → load → reverse engineer → compare round trip | 15 fixed (sync is a known limitation) |
| [`docs/mysql-bug-catalog.md`](docs/mysql-bug-catalog.md) | Same round trip against MySQL 8, plus synchronisation | 13 fixed |
| [`docs/db-ui-bug-catalog.md`](docs/db-ui-bug-catalog.md) | Connection selector/editor, reverse engineering, sync, export dialogs, plugins end to end | 19 fixed |
| [`docs/model-edit-bug-catalog.md`](docs/model-edit-bug-catalog.md) | Editing tables, fields, indices and relations; SQL export, MySQL/SQLite round trip and sync of a tool-created model; paste, undo/redo, Place Model; regions, notes, images and image export; Query mode editing on MySQL and SQLite (rounds 5-11 plus two regression passes) | 52 (40 fixed, 1 worked around, 1 hardened, 4 not bugs, 1 verified OK for the record, 1 not reproduced, 1 warning and 3 unconfirmed left open) |

[`docs/notes-to-myself.md`](docs/notes-to-myself.md) holds the working notes behind the fixes: root causes, LCL/GTK2 gotchas and the test-driving tricks.

## Project Structure

```
DBDesignerFork/
├── DBDesignerFork.lpi     # Lazarus project file
├── DBDesignerFork.lpr     # Main program source
├── README.md
├── src/                   # Core application source
│   ├── *.pas, *.lfm           # Main form, EER model engine, editors,
│   │                          #   palettes, options, UI test runner
│   ├── DBDesigner4.inc        # Shared compiler defines
│   ├── clx_shims/             # CLX → LCL / DBExpress → SQLDB compatibility layer
│   └── EmbeddedPDF/           # Built-in PDF document generation library
├── tests/                 # Standalone test programs and round-trip scripts
├── docs/                  # Documentation
│   ├── *-bug-catalog.md       # Test rounds: findings, fixes, verification
│   ├── notes-to-myself.md     # Working notes: causes, gotchas, tooling
│   ├── port-to-lazarus.md     # Porting guide
│   ├── port-to-lazarus-task-list.md  # Porting task checklist
│   └── *.txt                  # License texts, original build instructions
├── Plugins/               # Plugin projects
│   ├── DataImporter/          # Data import tool
│   ├── Demo/                  # Demo/example plugin
│   ├── HTMLReport/            # HTML report generator
│   ├── SimpleWebFront/        # Simple web front-end generator
│   └── TestDataGenerator/     # Test data as INSERT script or directly into a database
├── bin/                   # Runtime files (binaries are built here, not tracked)
│   ├── Data/                  # Configuration, settings, translations
│   ├── Doc/                   # User documentation (HTML + PDF manual)
│   ├── Examples/              # Example model files (XML)
│   ├── Gfx/                   # Graphics: cursors, icons, splash screen
│   └── *.dll, dbxoodbc/       # Delphi-era Windows drivers, kept for reference; unused by the port
├── lib/                   # Compiled unit output directory
├── test-base/             # Test XML models and SQL export reference files
├── SynEdit_clx_original/  # Original Delphi-era SynEdit source (reference only)
└── archive/               # Archived Delphi project files
```

## The Port

**The primary goal of this repository is to port DBDesigner Fork from Delphi/Kylix to [Free Pascal (FPC)](https://www.freepascal.org/) and the [Lazarus IDE](https://www.lazarus-ide.org/).** Delphi 7 and Kylix 3 are long discontinued; Free Pascal and Lazarus are free, actively maintained and cross-platform, a natural fit for a GPLv2 project.

### Approach

The port uses a **compatibility shim layer** ([`src/clx_shims/`](src/clx_shims/)) to minimize changes to the original source files:

- **CLX → LCL shims**: units like `QForms.pas`, `QControls.pas` that re-export LCL equivalents
- **Qt shim** (`qt.pas`): maps Qt widget types and key constants to LCL equivalents
- **Database shims** (`sqlexpr.pas`, `dbclient.pas`, `provider.pas`): wrap FPC's SQLDB (SQLite3 and MySQL 8 connectors) behind Delphi DBExpress-compatible interfaces; `sqlitelib.pas` and `mysqllib.pas` load the client libraries by their versioned names, `firebirdlib.pas` looks for the Firebird client library (VendorLib of the connection, next to the program, an installed server)
- **XML shims** (`xmlintf.pas`, `xmldoc.pas`, `xmldom.pas`): wrap `laz2_DOM` behind Delphi XML DOM interfaces

The bundled Delphi-era SynEdit was replaced by the SynEdit package that ships with Lazarus.

### Progress

All six projects (main application and five plugins) compile and run, on Linux and on Windows. Of the porting task list, 228 of 244 items are checked; the remaining ones are the untested areas listed under [Project Status](#project-status), the macOS build and the final clean-up (removing the shim layer in favour of direct LCL units). See [`docs/port-to-lazarus.md`](docs/port-to-lazarus.md) for the porting guide and [`docs/port-to-lazarus-task-list.md`](docs/port-to-lazarus-task-list.md) for the checklist.

### AI-Assisted Porting

The porting of this codebase from Delphi/CLX to Free Pascal/Lazarus, and the subsequent rounds of runtime testing and bug fixing, have been carried out by Artificial Intelligence with guidance and review from human developers. This includes the CLX-to-LCL migration, the compatibility shim layer, form conversions, database driver replacements, the automated test infrastructure, and the run-and-click testing on a real display that produced the bug catalogs.

This project serves as a real-world benchmark of how far AI-assisted software engineering has evolved — from understanding legacy codebases, to making architectural decisions, to producing working code across a ~150,000-line project and then debugging it interactively.

## Project Status

The port builds, launches and has been through eleven rounds of run-and-click testing on Linux (GTK2), each block of rounds followed by a combined regression pass on a single build (rounds 6-9b on d0fbc19, rounds 10-11 on 920a93c: no regressions, self-test 93 PASS / 0 FAIL both times). Treat the Linux build as an **early beta**: it is usable for modeling and for MySQL 8 / SQLite 3 work, but it has not been used in production.

The **Windows version is no longer a beta**: it is built, run and used on Windows 11 (64 bit), including Firebird, high DPI displays and the German user interface. What was done for it is listed under [Windows Version](#windows-version).

**Works and has been verified on a real display:**

- Modeling: creating, moving, editing and deleting tables, columns, indices, relations (1:1, 1:n, n:m), regions, notes and images; Table, Relation, Index, Region, Note and Image editors; Edit menu with Copy/Cut/Paste/Select All and keyboard shortcuts; z-order of regions; save and reload of XML models.
- Field editing on a blank model: in-place Column Name / DataType / Comment editors, the in-cell datatype drop-down and the "Set Datatype" popup submenu, Shift+click multi-row selection, prefix/postfix and index-name prompts, all Table Editor pages; typed datatypes and comments survive OK, reopen, save and reload.
- Undo/redo of delete, move and paste (the redo stack is cleared by a new edit, the close prompt appears after an undo); copy/paste within and across open models keeps FK indexes linked to their relations; Place Model from file (placement itself works, see limitations).
- Canvas regions, notes and images (rounds 10-10b): Region tool and Region Editor, region move with contents, notes with two-line non-ASCII text, PNG and 1-bpp BMP images that keep their colours and drag size after save/reopen; mixed selections of tables, regions, notes and images can be copied and pasted with unique names, and a multi-object delete is undone with every relation and FK column restored; new tables, notes, regions and images get names that are not already in use; Export Model / selected Objects as Image (PNG, JPEG) and Copy as Image run without an exception dialog.
- Query mode on MySQL and SQLite (round 11): query building by dragging tables onto the Query Drag Target, JOIN/WHERE/ORDER BY results matching the CLI, an editable result grid whose Apply Changes writes UPDATE/INSERT/DELETE back through the dataset shim, DATE/DATETIME/TIME shown and edited as ISO text (also stored as text on SQLite), empty results shown as an empty grid, stored SQL commands and the history saved with the model, Ctrl+S in both modes, rename dialog and every other string prompt closable with Escape.
- SQL export: CREATE scripts for MySQL and SQLite load into the real databases without errors (checked with `tests/mysql-roundtrip.sh` and `tests/sqlite-roundtrip.sh`).
- **MySQL 8**: connect, reverse engineering (columns, auto-increment, UNIQUE and prefix indexes, native foreign keys, column and table comments, the table engine), synchronisation of column changes, Query mode, committed DML. A tool-created model with typed datatypes and comments went export → load → reverse engineer → compare → sync without data loss (round 8).
- **SQLite 3**: connect, reverse engineering through the pragma tables (columns, primary keys, AUTOINCREMENT, indexes, foreign keys), Query mode, committed DML; the read lock is released when idle so other writers are not blocked.
- Connection selector and editor, DBConn.ini persistence, real server error messages on failed logins.
- All four plugins start; DataImporter (CSV import) and SimpleWebFront (PHP generation) and HTMLReport have been exercised end to end.
- Options dialogs, Datatype editor, Page Setup, Navigator, palettes, window arrangement.

**Known limitations:**

- Only the **MySQL**, **SQLite** and **Firebird** connectors are linked. Oracle, MS SQL Server and ODBC still appear in the driver list but cannot connect.
- **Firebird** (`src/DBEERFirebird.pas`, Firebird 3 or newer) has only been run through `tests/TestFirebirdSync.pas` (Firebird 5, embedded and over TCP), not through the dialogs. A connection without host name uses the embedded engine of the client library and creates a missing database file; `VendorLib` may hold the full path of `fbclient.dll`. The model keeps its MySQL datatypes, the synchronisation maps them (DATETIME to TIMESTAMP, TEXT to BLOB SUB_TYPE TEXT, AUTO_INCREMENT to an identity column, ...). Every DDL statement is committed on its own, a failing one is logged and the sync goes on. Firebird cannot rename a table (it is created anew, the rows are copied, the old one is dropped) and cannot turn an existing column into an identity column. The SQL export for the FireBird target uses the same datatype mapping and names (`src/FirebirdSQL.pas`): `CONSTRAINT ... FOREIGN KEY`, `CREATE INDEX` statements, `COMMENT ON`, reserved words in quotes, no `DROP TABLE IF EXISTS`. Without the generator-and-trigger option an auto increment column is written as an identity column (Firebird 3). The test loads both script variants into a fresh database with `isql`.
- **Synchronisation against SQLite** (`src/DBEERSQLiteSync.pas`) has only been run through `tests/TestSQLiteSync.pas`, not through the dialog. SQLite has no ALTER COLUMN: renamed, appended and plainly dropped columns use ALTER TABLE, every other change rebuilds the table (copy the rows, drop, rename, recreate indices and triggers) in one transaction per table. A rebuild is refused while `PRAGMA foreign_keys` is on for the connection.
- Dragging a datatype from the palette onto the Table Editor grid does nothing while the editor is modal (it would need a non-modal Table Editor); use the "Set Datatype" popup submenu of the column grid instead.
- SQL export writes no `ENGINE` clause for MyISAM tables (MySQL's default engine applies).
- Placing a model from file (Add/Link Model) is not undoable, as in the original.
- Export selected Objects as Image paints from the model origin instead of cropping to the selection (inherited).
- The query result grid shows DECIMAL values through a float conversion, so trailing zeros are trimmed (`14.20` is displayed as `14.2`).
- Unconfirmed: typing over an already filled DataType cell after a single click may not replace the value (model-edit #34); an empty one-column result right after a syntax-error dialog (#47) and a first Execute after connecting that does nothing (#51) were each seen once and could not be reproduced under probes.
- Self relations are not guessed by reverse engineering.
- Not yet tested: PDF export, print and page preview output, ERwin import, Open/Save model in database, the Column Parameters dialog, undo granularity inside the Table and Relation editors, the query grid's Export Records / Print Records to PDF and BLOB viewer.
- macOS has not been built or run. The run-and-click test rounds above were done on Linux; on Windows the areas listed under [Windows Version](#windows-version) were checked.
- One GLib-CRITICAL warning on stderr remains (Return in the Table Editor grid followed by Return in the name editor; harmless).

Every finding, fix and verification is recorded in the bug catalogs under `docs/` (see [Testing](#testing)).

## Windows Version

The port had only been compiled and run on Linux. Since October 2026 it is built and used on Windows 11 (64 bit) with Lazarus 4.4 / FPC 3.2.2 (`x86_64-win64`), and this is the list of what was changed for it. **New entries are added at the top of each block with every change that is pushed.**

**Build and start**

- Setup program: `installer/DBDesignerFork.iss` is an Inno Setup script (written for Inno Setup 7). After building the program and the plugins, `ISCC.exe installer\DBDesignerFork.iss` writes `installer/Output/DBDesignerFork-<version>-win64-setup.exe`. It installs the program, the plugins, `Data`, `Gfx`, `Doc` and the order example, for all users or for the current user, in English or German. The 64 bit client libraries (`sqlite3.dll`, `libmySQL.dll` and what it needs) are packed when they lie in `bin`; they are not part of the repository. `fbclient.dll` is not packed.
- The version is 2.0.0.*build*. The start picture and *Help > About* read it from the version info of the program (`GetProgramVersionStr` in `src/GlobalSysFunctions.pas`) instead of a fixed "Version 1.5". The build number is counted up by Lazarus: `lazbuild` does it only at a build of everything (`lazbuild -B DBDesignerFork.lpi`) and then writes the next number to `DBDesignerFork.lpi`, so this file is changed by such a build.
- Version info of the program: it is set in the project options of Lazarus (`DBDesignerFork.lpi`, *Project Options > Version Info*). Before it was a fixed 1.0.0.0 block inside a binary `.res` file. The icon and the application manifest stay in `src/AppResources.res` (was `src/DBDesignerFork.res`; Lazarus writes its own `DBDesignerFork.res` with the version info at every build).
- Builds on Windows: the Delphi-era Windows branches of the source never went through FPC (compiler version check of the XML parser, CLX/Qt window workarounds, native dialog switches, `/tmp` in the tests).
- Main program and plugins are Windows GUI applications (no console window); `--selftest` writes its result to the log file only.
- Application manifest: visual styles of Windows (Common Controls 6) instead of the Windows 95 look.
- The start picture is shown again while the program loads and under *Help > About* (it was a PNG loaded as a bitmap and failed).
- The saved position, size and state of the main window are restored; the floating query editor keeps its position.
- The model window follows the size of the main window again (it stayed a small rectangle after restoring and maximizing).

**High DPI displays**

- The program is DPI aware (system DPI): Windows no longer magnifies the window as a blurred bitmap.
- The dialogs are scaled with the application font, the main window, the palettes and the docked query editor with the DPI of the display, including the pixel sizes that are set in the code (`TDMMain.FitFormLayout`, `src/UIScale.pas`).
- The glyphs of the buttons, the images and the image lists are enlarged smoothly with hard transparent edges; custom drawn lists (table editor grid, connection tree, model and datatype palettes) follow the size of the symbols.
- The model is drawn in the scale of the display, so 100 % keeps its size; zoom, scroll position and position markers are stored independent of the DPI, printing and image export are unchanged.
- Window positions and sizes, the width of the docked palettes and the sizes of the query panel are stored in the pixels of a 96 DPI display.
- The cursors of the work tools are created in the scale of the display - and no longer invert a square around the pointer (a fault of the port that was visible on Windows).
- The plugins are DPI aware and scaled in the same way.

**Dialogs and palettes**

- The dialogs to open and to place a model offer "All files (*.*)" as a second file type.
- Model palette: the tables in the list have the colour of their region again; a selected table keeps the colour and is marked by a small square behind its name. The context menu opens on a right click on the table name, and a selected node keeps its icon.
- Every dialog was gone through with `--screenshots`: the forms are laid out in fixed pixels for a font of 8 points and are now fitted to the application font; the contents of group boxes are no longer cut off (CLX places them relative to the frame, the LCL below the caption).
- Right justified and centred labels keep their place in front of their field instead of sticking to the control before them.
- Palettes and status bar use the application font; there is a splitter between the palettes and the model; the tab strips of the palettes are painted in the right colours.
- Connection selector: the tree is filled completely and uses the system colours; the linked models dialog has its designed size.
- The name of a region is black, or white on a dark region (the grey was hard to read).
- The SQL editor of the query mode no longer starts with its component name as text.

**Language and character sets**

- Umlauts in the user interface: the translation files are Latin-1 and are converted when they are loaded.
- Umlauts in model files: read and written in the Windows code page as the original program did, shown correctly in the LCL (UTF-8).
- The German translation is complete, including the palettes and many controls that could not be translated before (form captions, list items, list columns, hints).
- The plugins use the application font of the main program and its translations for the dialogs they share with it.

**Databases**

- **Firebird** (3 or newer; tested with Firebird 5, server and embedded): connect, reverse engineering, synchronisation and an SQL export that Firebird accepts (datatype mapping, reserved words, identity columns, `CONSTRAINT ... FOREIGN KEY`, `CREATE INDEX`, comments, triggers).
- **SQLite**: database synchronisation (ALTER TABLE where SQLite can, otherwise a rebuild of the table in one transaction).
- 64-bit client libraries are loaded from the program directory.

**Model**

- Several open models can be shown at once: "Tile" and "Cascade" of the Windows menu lay the models out in the model area, each with a title bar. A click into a model makes it the active one; a double click on its title bar or its entry in the Windows menu shows it alone again.
- Large models: the work area matches the navigator right after loading (the canvas size was read after the zoom, so the lower right corner could not be reached).
- Empty image data in a model file no longer raises an error.

**New**

- **Test Data Generator plugin**: INSERT statements for the selected tables in the order of their foreign keys, values by datatype and column name in German or English, unique keys, for FireBird, MySQL, Oracle, PostgreSQL, SQL Server and SQLite; as a script to copy or save, or executed in a database in one transaction. Executed in a database that has rows already, the new rows are added beside them: their keys go on after the highest existing key (or the existing rows are deleted first, if that is chosen).
- `--screenshots <dir>` saves a picture of every dialog, the main window in both modes and the cursors, to check the layout after a change.

**Checked on Windows**

- `--selftest` (0 failures), `tests/TestSQLiteSync`, `tests/TestFirebirdSync` (embedded and over TCP) and `tests/TestTestDataGen` after every change; all dialogs and the plugins with `--screenshots` and screenshots at 144 DPI (150 % scaling), application font 8 and 10 points.
- Not part of these checks: MySQL connections, a display of 96 DPI, a second display with another DPI (Windows magnifies the window there), PDF export and printing.


## License

This project is licensed under the **GNU General Public License v2**. See [`docs/Copying.txt`](docs/Copying.txt) for the full license text.

## Contributing

Contributions to the FPC/Lazarus port are highly welcome: testing on macOS, exercising the untested areas above, porting the remaining database connectors, or improving documentation. Please record what you tested and what you found in the style of the bug catalogs in `docs/`.
