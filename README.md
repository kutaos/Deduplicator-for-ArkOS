# Deduplicator for ArkOS (R36S / RG351 etc.)

`Deduplicator.sh` is an on-device ROM deduplication utility for ArkOS that helps you find duplicate ROMs by **content hash (MD5)** and safely move duplicates (and optionally broken ZIP archives) into a restorable **DedupBin** instead of deleting them.

This project is designed for handheld console workflows: it runs from the **ArkOS Tools** menu and uses a `dialog` UI rendered on `/dev/tty1`, with optional gamepad-to-keyboard mapping via `gptokeyb`. 

---
## Support

If this project helps you, you can support it with a one-time donation:

- GitHub Sponsors (via the **Sponsor** button on this repository / my profile)
- Buy Me a Coffee: https://buymeacoffee.com/kutaos
- PayPal: https://www.paypal.me/kutaos
---

## Key Features

### Safe-by-design file handling

* **No permanent deletion during deduplication**

  * Duplicate ROM files are **moved** to `DedupBin` (they can be restored later). 
* A **permanent delete** exists only as an explicit tool: **“Delete DedupBin (permanently)”**. 

### Content-based deduplication (MD5)

* Duplicates are identified by **MD5 of ROM content**, not by filename. 
* For ZIP files, MD5 is computed from the **single valid ROM file inside the ZIP** (see ZIP rules below). 

### Two deduplication modes

* **PER** – deduplicate **within each emulator** (optionally restrict scanning to one chosen emulator folder). 
* **ALL** – deduplicate **across all emulators together** (global hash space). 

### ZIP handling and broken ZIP management

* ZIP archives are supported for hashing when:

  * the archive contains **exactly one ROM file**, and
  * the inner ROM extension matches allowed extensions for that emulator. 
* Broken ZIPs are:

  * logged as `BROKEN_ZIP`,
  * counted in the Summary,
  * optionally moved to DedupBin (same safety model as duplicates). 

### Empty MD5 outputs are ignored

* If a computed MD5 equals the “empty stream” hash (`d41d8…`), that candidate is **excluded from comparison** (not logged as broken). 

### Subfolder support

* ROM candidates are collected recursively under `/roms/<emu>/...` (and `/roms2/<emu>/...`), excluding `images/` and `videos/` subpaths. 

### Log with summary and end marker

* Writes a detailed log to:
  `/opt/system/Tools/Deduplicator.log` 
* Summary is inserted near the top (after `Mode : ...`).
* A clear end marker is appended:
  `----- END OF LOG FILE (YYYY-MM-DD HH:MM:SS) -----` 

### Extra tools beyond deduplication

From the main menu, the script also provides:

* View log (with automatic line wrapping for small screens) 
* Delete log 
* Media cleanup: move orphaned images/videos into DedupBin 
* Restore everything from DedupBin back to ROM folders (non-destructive restore; no overwrite) 
* Purge DedupBin permanently (explicit destructive operation) 

---

## Installation (ArkOS)

1. Copy `Deduplicator.sh` into your Tools folder on the SD card you use for ROM storage:

   * If you store ROMs on SD1:
     `roms/tools/`
   * If you store ROMs on SD2:
     `roms2/tools/`

2. Safely eject the SD card(s), boot into ArkOS, open **Tools**, and run **Deduplicator.sh**.

That’s it—no extra installation steps are required. 

---

## Requirements

This script assumes an ArkOS environment with:

* `bash`
* `dialog`
* standard core utilities: `find`, `stat`, `awk`, `sed`, `fold`, `expand` (optional), `md5sum`
* ZIP support via `unzip` (Info-ZIP)
* optional controller mapping: `/opt/inttools/gptokeyb` and `/opt/inttools/keys.gptk` 

The script elevates to root automatically (via `sudo`) because ArkOS input handling and `gptokeyb` mapping typically require it. 

---

## Main Menu Overview

When launched, you get a `dialog` menu with these actions: 

1. **Deduplicate ROMs**
2. **Move duplicates / broken ZIP to DedupBin**
3. **View Deduplicator.log**
4. **Move orphaned images/videos to DedupBin**
5. **Restore from DedupBin**
6. **Delete Deduplicator.log**
7. **Delete DedupBin (permanently)**
8. **Exit**

---

## How Deduplication Works

### Disk selection

You choose which SD card root to scan:

* `/roms` (SD1) or
* `/roms2` (SD2) 

### Mode selection

You choose one of:

* **PER**: only within the same emulator folder
* **ALL**: across all emulators together 

If you select **PER**, you can further choose:

* all emulators, or
* a specific emulator folder (filter). 

---

## Dedup Pipeline Stages

### Stage 1/3 — Collect ROM candidates

The script recursively scans the chosen root (`/roms` or `/roms2`) and collects candidate files when:

* they are inside a valid emulator folder,
* the emulator folder exists in `EXT_MAP`,
* the file extension matches allowed extensions for that emulator,
* the path is not under `images/` or `videos/`,
* the folder is not in ignored roots such as `bios`, `tools`, `ports`, `DedupBin`, etc. 

If no candidates are found:

* a friendly message is shown,
* the log Summary anchor is replaced with a “No ROM files were found.” note so the log does not look truncated. 

---

### Stage 2/3 — Read metadata (mtime/size) and detect ZIP inner ROM

For each candidate:

* Reads physical file size and modification time (mtime) via `stat`. 
* If the candidate is a `.zip`:

  * Lists contents via `unzip -Z1`.
  * Filters inner files by allowed extensions for that emulator (`EXT_MAP[emu]`).
  * Accepts the ZIP only if it contains **exactly one valid ROM** inside. 
  * If `unzip` fails or list is empty, it is logged as `BROKEN_ZIP` and excluded. 

UI:

* A gauge is displayed with percent + current filename from the emulator folder. 

---

### Stage 3/3 — Compute MD5 hashes

For each valid candidate:

* If it is a normal file: `md5sum <file>`.
* If it is a ZIP (with one valid inner ROM):

  * streams inner ROM with `unzip -p` (with safe escaping for `[ ] * ?`) 
  * runs a size sanity check (`wc -c`) and then computes MD5.
  * logs `BROKEN_ZIP` if streaming/MD5 pipeline fails. 
* If the MD5 equals the empty-stream hash (`d41d8…`), the file is ignored (excluded from comparison). 

UI:

* A gauge is displayed with percent + current filename. 

---

## Duplicate Selection Rule (Which File Is Kept)

For each MD5 group with 2+ members:

* The script selects the **oldest file** by modification time (`mtime`) as the **KEEP** base.
* All newer members become **DUP** entries. 

This means:

* the file you copied earlier (older timestamp) is more likely to be kept,
* newer duplicates are moved to DedupBin if you choose to move them.

---

## What Happens After the Scan

At the end of scanning:

1. The log is finalized:

   * Summary is inserted after the `__SUMMARY__` anchor near the top
   * End marker is appended to the log 
2. The script shows:
   `Duplicate scan completed... Details ... in: <root>/tools/Deduplicator.log` 
   (Note: the actual log write path is `/opt/system/Tools/Deduplicator.log`.)
3. If duplicates were found, you are prompted to **move duplicates to DedupBin**. 
4. If broken ZIPs were found, you are prompted to **move broken ZIP files to DedupBin** (even if you declined duplicate moving). 

---

## DedupBin Layout (Where Files Are Moved)

When you move duplicates or broken ZIPs, files are moved to:

`<ROOT>/DedupBin/<ROOT_NAME>/...`

Where:

* `<ROOT>` is `/roms` or `/roms2`
* `<ROOT_NAME>` is `roms` or `roms2` (used to namespace the bin) 

The script preserves the relative path under the root, so restore can put files back into their original emulator folders.

---

## Restore From DedupBin

Restore is an “all at once” operation:

* Scans DedupBin and shows file count and size.
* Restores everything back to ROM folders.
* **Does not overwrite existing files**: if a destination file already exists, it is skipped.
* Removes empty directories left behind in DedupBin after restore. 

---

## Media Cleanup (Orphaned Images/Videos)

The cleanup tool detects media that no longer matches any ROM basename:

* Images: `*/images/*-image.*`
* Videos: `*/videos/*-video.*`
* Also handles `downloaded_images` and `downloaded_videos` with subfolder rules. 

Orphaned media files can be moved into DedupBin (same non-destructive behavior). 

---

## Log Viewer

“View Deduplicator.log” shows the log in a textbox optimized for small screens:

* Creates a temporary wrapped copy using `expand` (if available) and `fold -s` to avoid horizontal scrolling. 

---

## Notes and Limitations

### ZIP layout requirement

ZIPs are only processed if they contain **exactly one** valid ROM file for the emulator. ZIPs with:

* zero valid ROMs, or
* multiple valid ROMs
  are excluded from comparison (not necessarily logged as broken). 

### Archive types other than ZIP

`EXT_MAP` includes extensions like `7z` for some emulators, but the current “archive-aware” logic implemented in this version is ZIP-focused (`unzip` pipeline). Non-ZIP archive files are treated like normal candidates only if they pass extension filtering, but hashing relies on normal file hashing unless ZIP logic is used. 

### Performance

MD5 computation requires reading full file contents (and ZIP decompression for ZIP candidates). Large sets and slow SD cards may cause visible pauses in Stage 3/3. 

---

## Troubleshooting

### “The UI freezes during Stage 3/3”

This usually means the script is computing MD5 for a slow-to-read file or a ZIP that decompresses slowly. The gauge updates after each file completes, so a long file will look like a “freeze.” 

### “Controls don’t work / gamepad doesn’t navigate dialog”

The script uses `gptokeyb` when available and expects `/opt/inttools/keys.gptk`. It also restarts mappings cleanly to avoid stacking. 

### “Where is the log file?”

The script writes the log to:

* `/opt/system/Tools/Deduplicator.log` 

The UI message references `<ROOT>/tools/Deduplicator.log` (root-relative text), but the actual write location is the `/opt/system/Tools/` path.

---

## License

...

---

## Credits

Created by **Taras Kukhar**. 
