#!/bin/bash
###############################################################################
# Deduplicator for ArkOS by Taras Kukhar v1.1 — dialog build
# GitHub: https://github.com/kutaos/Deduplicator-for-ArkOS
# - Runs from ArkOS Tools on-device (dialog UI on /dev/tty1)
# - Never deletes ROMs during dedup: duplicates are moved to DedupBin (restorable)
# - Dedup modes:
#     PER: within emulator (optionally limit scan to one selected emulator)
#     ALL: across all emulators together
# - ZIP handling: computes MD5 of the single valid ROM inside ZIP (per EXT_MAP rules)
# - Broken ZIP detection: logs broken archives and can optionally move them to DedupBin
# - Ignores files producing an empty MD5 (excluded from comparison)
# - Supports subfolders, produces Deduplicator.log with statistics
# - Tools: media cleanup (orphaned images/videos), restore from DedupBin,
#          view/delete log, purge DedupBin permanently
###############################################################################


# --- Require root to make game console controls to work---
if [ "$(id -u)" -ne 0 ]; then
  exec sudo -- "$0" "$@"
fi

# ---------------- ArkOS TTY / ENV SETUP ----------------
CURR_TTY="/dev/tty1"

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export TERM=linux
unset FBTERM

# Clear screen, hide cursor, init dialog
printf "\033c" > "$CURR_TTY"
printf "\e[?25l" > "$CURR_TTY"
dialog --clear
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Console font
if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
  setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz 2>/dev/null || true
else
  setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz 2>/dev/null || true
fi

VERSION="v1.1"

printf "\033c" > "$CURR_TTY"
printf "Deduplicator for ArkOS by Taras Kukhar $VERSION\nPlease wait..." > "$CURR_TTY"
sleep 1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/opt/system/Tools/Deduplicator.log"

###############################################################################
# EXT_MAP — ArkOS ROM extensions per emulator folder
###############################################################################
declare -A EXT_MAP=(
  [3do]="iso bin chd cue"
  [advision]="zip"
  [alg]="alg"
  [amiga]="adf hdf lha zip"
  [amigacd32]="cue ccd chd lha nrg mds iso m3u"
  [amstradcpc]="cpc dsk zip 7z"
  [gx4000]="cpr dsk zip"
  [apple2]="dsk sh do po apple2 zip"
  [apple2gs]="2mg dsk po woz"
  [arcade]="7z fba fba.zip zip"
  [arduboy]="hex"
  [atari2600]="a26 bin gz zip 7z"
  [atari5200]="a52 bin xtc zip 7z"
  [atari7800]="a78 bin zip 7z"
  [atarijaguar]="j64 jag zip 7z"
  [atarijaguarcd]="j64 jag zip 7z"
  [atarilynx]="lnx zip 7z"
  [atarist]="st msa stx dim ipf"
  [atomiswave]="bin dat lst zip"
  [c64]="crt d64 d71 d80 d81 d82 g41 g64 p00 prg tape t64 tap x64 zip"
  [c64h]="crt d64 d71 d80 d81 d82 g41 g64 p00 prg tape t64 tap x64 zip"
  [coco]="cas dsk rom"
  [coleco]="bin col rom zip 7z"
  [cps1]="7z zip"
  [cps2]="7z zip"
  [cps3]="7z zip"
  [daphne]="daphne"
  [dc]="cdi chd cue gdi iso"
  [defenceforceorg_yazs_sdk]="bin"
  [doom]="iwad iwad.zip ipk3 ipk3.zip pk3 pk3.zip wad wad.zip"
  [dos]="bat com cue exe img iso vhd vhdx"
  [doszippedgames]="zip"
  [dragon32]="cas dsk"
  [drastic]="drc"
  [easyrpg]="easyrpg zip"
  [ecwolf]="pk3"
  [emersonarcadia2001]="bin a26 a52 rom zip"
  [enterprise]="7z com dsk prg sna tap trd zip"
  [fbneo]="7z zip"
  [fds]="fds nes qd zip 7z"
  [flashPlayer]="swf"
  [fmtowns]="bin chd cue iso zip"
  [fpinball]="fpt"
  [gamelion]="rom"
  [gameandwatch]="mgw"
  [gamecom]="gc zip"
  [gamegear]="7z gg zip"
  [gb]="gb gbc dmg zip 7z"
  [gb2players]="gb gbc dmg zip 7z"
  [gba]="7z gba zip"
  [gbah]="gba"
  [gbc]="gb gbc dmg zip 7z"
  [gbch]="gbc"
  [gbh]="gb"
  [gc]="ciso gcm iso nkit.iso nkit.gcz"
  [genesis]="32x 7z bin gen md smd zip"
  [genh]="32x 7z bin gen md smd zip"
  [genesis-wide-screen]="32x 7z bin gen md smd zip"
  [genesis-japan]="32x 7z bin gen md smd zip"
  [genesis-multi-region]="32x 7z bin gen md smd zip"
  [genesis-usa]="32x 7z bin gen md smd zip"
  [genesisdx]="32x 7z bin gen md smd zip"
  [genh2players]="32x 7z bin gen md smd zip"
  [ggh]="gg"
  [gw]="mgw"
  [intellivision]="bin int rom zip 7z"
  [j2me]="jar"
  [jaguar]="j64 jag zip 7z"
  [jaguarcd]="j64 jag zip 7z"
  [kodi]="kodi"
  [laserdisc]="chd"
  [lcdgames]="mgw"
  [lutris]="lutris"
  [mame]="7z zip"
  [mame-advmame]="zip"
  [mame-libretro]="7z zip"
  [mame2003]="7z zip"
  [mame2003-plus]="7z zip"
  [mame2010]="7z zip"
  [mame2015]="7z zip"
  [mame2016]="7z zip"
  [mastersystem]="7z sms zip"
  [megacd]="bin chd cue iso"
  [megadrive]="32x 7z bin gen md smd zip"
  [megadrive-wide-screen]="32x 7z bin gen md smd zip"
  [megadrive-japan]="32x 7z bin gen md smd zip"
  [megadrive-multi-region]="32x 7z bin gen md smd zip"
  [megadrive-usa]="32x 7z bin gen md smd zip"
  [megadrivedx]="32x 7z bin gen md smd zip"
  [model2]="7z zip"
  [model3]="7z zip"
  [msdos]="bat com cue exe img iso vhd vhdx"
  [msx]="cas dsk fmp rom zip 7z"
  [msx2]="cas dsk fmp rom zip 7z"
  [n64]="n64 v64 z64 zip 7z"
  [n64dd]="ndd zip 7z"
  [naomi]="7z bin dat lst zip"
  [naomigd]="7z bin dat gdi lst zip"
  [nds]="zip nds"
  [nes]="nes zip 7z"
  [famicom]="nes zip 7z"
  [odyssey2]="bin"
  [openbor]="pak"
  [palm]="img prc"
  [pc98]="cmd d88 fdi hdi zip"
  [satellaview]="bs sfc smc zip 7z"
  [scummvm]="scummvm"
  [sega32x]="32x 7z bin md smd zip"
  [segacd]="bin chd cue iso"
  [solarus]="solarus zip"
  [sgb]="gb gbc dmg zip 7z"
  [supergrafx]="pce sgx cue ccd chd zip 7z"
  [snes]="sfc smc zip 7z"
  [sfc]="sfc smc zip 7z"
  [snesmsu1]="smc sfc zip 7z"
  [snes_hacks]="smc fig bs st sfc gd3 gd7 dx2 bsx swc zip 7z"
  [coco3]="bin cas ccc dsk rom wav zip"
  [ti99]="ctg"
  [uzebox]="uze"
  [vectrex]="vec zip 7z"
  [videopac]="bin zip"
  [tvc]="cas"
)

declare -A EMU_LABEL=(
  [3do]="3DO"
  [advision]="Adventure Vision"
  [alg]="American Laser Games"
  [amiga]="Commodore Amiga"
  [amigacd32]="Amiga CD32"
  [amstradcpc]="Amstrad CPC"
  [gx4000]="Amstrad GX4000"
  [apple2]="Apple II"
  [apple2gs]="Apple IIGS"
  [arcade]="Arcade"
  [arduboy]="Arduboy"
  [atari2600]="Atari 2600"
  [atari5200]="Atari 5200"
  [atari7800]="Atari 7800"
  [atarijaguar]="Atari Jaguar"
  [atarijaguarcd]="Atari Jaguar CD"
  [atarilynx]="Atari Lynx"
  [atarist]="Atari ST"
  [atomiswave]="Sega Atomiswave"
  [c64]="Commodore 64"
  [c64h]="Commodore 64 (Hacks)"
  [coco]="Tandy Color Computer"
  [coleco]="ColecoVision"
  [cps1]="Capcom CPS-1"
  [cps2]="Capcom CPS-2"
  [cps3]="Capcom CPS-3"
  [daphne]="Daphne LaserDisc"
  [dc]="Sega Dreamcast"
  [defenceforceorg_yazs_sdk]="YAZS SDK (Defence Force)"
  [doom]="DOOM Engine"
  [dos]="MS-DOS"
  [doszippedgames]="DOS (Zipped Games)"
  [dragon32]="Dragon 32"
  [drastic]="Nintendo DS (DraStic)"
  [easyrpg]="EasyRPG"
  [ecwolf]="ECWolf (Wolfenstein 3D)"
  [emersonarcadia2001]="Emerson Arcadia 2001"
  [enterprise]="Enterprise 128"
  [fbneo]="FinalBurn Neo"
  [fds]="Famicom Disk System"
  [flashPlayer]="Flash Player"
  [fmtowns]="FM Towns"
  [fpinball]="Future Pinball"
  [gamelion]="Gamelion"
  [gameandwatch]="Game & Watch"
  [gamecom]="Tiger game.com"
  [gamegear]="Sega Game Gear"
  [gb]="Game Boy"
  [gb2players]="Game Boy (2 Players)"
  [gba]="Game Boy Advance"
  [gbah]="Game Boy Advance (Hacks)"
  [gbc]="Game Boy Color"
  [gbch]="Game Boy Color (Hacks)"
  [gbh]="Game Boy (Hacks)"
  [gc]="Nintendo GameCube"
  [genesis]="Sega Genesis / Mega Drive"
  [genh]="Genesis / Mega Drive (Hacks)"
  [genesis-wide-screen]="Genesis Wide Screen"
  [genesis-japan]="Genesis Japan"
  [genesis-multi-region]="Genesis Multi-Region"
  [genesis-usa]="Genesis USA"
  [genesisdx]="Genesis Deluxe"
  [genh2players]="Genesis (2 Players Hacks)"
  [ggh]="Game Gear (Hacks)"
  [gw]="Game & Watch"
  [intellivision]="Intellivision"
  [j2me]="J2ME Mobile"
  [jaguar]="Atari Jaguar (Standalone)"
  [jaguarcd]="Atari Jaguar CD (Standalone)"
  [kodi]="Kodi"
  [laserdisc]="LaserDisc"
  [lcdgames]="LCD Handheld Games"
  [lutris]="Lutris"
  [mame]="MAME"
  [mame-advmame]="AdvanceMAME"
  [mame-libretro]="MAME (Libretro)"
  [mame2003]="MAME 2003"
  [mame2003-plus]="MAME 2003-Plus"
  [mame2010]="MAME 2010"
  [mame2015]="MAME 2015"
  [mame2016]="MAME 2016"
  [mastersystem]="Sega Master System"
  [mastersystemh]="Master System (Hacks)"
  [megacd]="Sega Mega CD"
  [megaduck]="Mega Duck"
  [megadrive]="Sega Mega Drive"
  [megadrive-wide-screen]="Mega Drive Wide Screen"
  [megadrive-japan]="Mega Drive Japan"
  [megadrive-multi-region]="Mega Drive Multi-Region"
  [megadrive-usa]="Mega Drive USA"
  [megadrivedx]="Mega Drive Deluxe"
  [model2]="Sega Model 2"
  [model3]="Sega Model 3"
  [msdos]="MS-DOS"
  [msu-md]="Mega Drive MSU-MD"
  [msuh]="MSU Hacks"
  [msx]="MSX"
  [msx2]="MSX2"
  [n64]="Nintendo 64"
  [n64dd]="Nintendo 64DD"
  [naomi]="Sega Naomi"
  [naomigd]="Sega Naomi GD-ROM"
  [nds]="Nintendo DS"
  [nes]="Nintendo Entertainment System"
  [famicom]="Nintendo Famicom"
  [odyssey2]="Magnavox Odyssey²"
  [openbor]="OpenBOR"
  [palm]="Palm OS"
  [pc98]="NEC PC-98"
  [satellaview]="Satellaview"
  [scummvm]="ScummVM"
  [sega32x]="Sega 32X"
  [segacd]="Sega CD / Mega CD"
  [solarus]="Solarus Engine"
  [sgb]="Super Game Boy"
  [supergrafx]="PC Engine SuperGrafx"
  [snes]="Super Nintendo (SNES)"
  [sfc]="Super Famicom"
  [snesmsu1]="SNES MSU-1"
  [snes_hacks]="SNES (Hacks)"
  [coco3]="Tandy Color Computer 3"
  [ti99]="TI-99/4A"
  [uzebox]="Uzebox"
  [vectrex]="Vectrex"
  [videopac]="Philips Videopac"
  [tvc]="TVC-32/64"
)

# Emulator filter for dedup_scan:
# empty  -> scan all emulators
# non-empty -> scan only that single emulator (EXT_MAP key)
EMU_FILTER=""

# Let user choose emulator scope: all emulators or a single emulator.
# Result is stored in EMU_FILTER:
#   ""       -> scan all emulators
#   "<name>" -> scan only that emulator (EXT_MAP key)
select_emulator_filter() {
  local EMU_LIST_STR emu
  local -a ITEMS

  # Build sorted list of emulator names from EXT_MAP
  EMU_LIST_STR=$(printf '%s\n' "${!EXT_MAP[@]}" | sort)

  ITEMS=()
  # First entry: ALL emulators (default)
  ITEMS+=("ALL" "All emulators")

  # Then each emulator as a separate option
  while IFS= read -r emu; do
    [[ -z "$emu" ]] && continue
    # Use human-readable emulator label if available, otherwise fallback to folder name
    local label="${EMU_LABEL[$emu]:-$emu}"
    ITEMS+=("$emu" "$label")
  done <<< "$EMU_LIST_STR"

  local choice
  choice=$(dialog --output-fd 1 \
    --title "Deduplicator $VERSION" \
    --menu "Choose emulator scope:" \
    18 70 15 \
    "${ITEMS[@]}" \
    2>"$CURR_TTY") || {
      # Cancel / ESC -> back to main menu
      EMU_FILTER=""
      return 1
    }

  if [[ "$choice" == "ALL" ]]; then
    EMU_FILTER=""
  else
    EMU_FILTER="$choice"
  fi

  return 0
}

# ---------------- Gamepad → Keyboard (gptokeyb) --------
start_gptokeyb() {
  # Enable gamepad-to-keyboard mapping for this script
  GPTPID=""

  if [ -x /opt/inttools/gptokeyb ]; then
    # uinput permissions (like other ArkOS tools); ignore failure if not root
    [[ -e /dev/uinput ]] && chmod 666 /dev/uinput 2>/dev/null || true
    export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"

    # Avoid stacking multiple mappings for this script
    local tgt
    tgt="$(basename "$0")"

    pkill -f "gptokeyb.*-1[[:space:]]+$tgt" >/dev/null 2>&1 || true

    # Start gptokeyb for this script
    # Use the system-wide mapping if available (no temporary config file).
    if [ -f /opt/inttools/keys.gptk ]; then
      /opt/inttools/gptokeyb -1 "$tgt" -c /opt/inttools/keys.gptk >/dev/null 2>&1 &
    else
      /opt/inttools/gptokeyb -1 "$tgt" >/dev/null 2>&1 &
    fi
    GPTPID=$!
  fi
}

stop_gptokeyb() {
  # Stop gptokeyb started for this script
  local tgt
  tgt="$(basename "$0")"
  pkill -f "gptokeyb.*-1[[:space:]]+$tgt" >/dev/null 2>&1 || true
}

cleanup_exit() {
  # show cursor back
  printf "\e[?25h" > "$CURR_TTY"

  stop_gptokeyb

  printf "\033c" > "$CURR_TTY"
  exit 0
}
trap cleanup_exit EXIT SIGINT SIGTERM

###############################################################################
# IGNORE ROOT DIRS
###############################################################################
IGNORE_ROOT_DIRS=(
  "backup" "bios" "launchimages" "movies"
  "ports" "tools" "videos"
  "System Volume Information" "DedupBin"
)

is_ignored_dir() {
  local name="$1"
  for d in "${IGNORE_ROOT_DIRS[@]}"; do
    [[ "$name" == "$d" ]] && return 0
  done
  return 1
}

###############################################################################
# DIALOG HELPERS
###############################################################################
safe_infobox() {
  local msg="$1" h="$2" w="$3"
  dialog --title "Deduplicator $VERSION" --infobox "$msg" "$h" "$w" >"$CURR_TTY" 2>&1
}

show_info() {
  local msg="$1"
  dialog --title "Deduplicator $VERSION" --infobox "$msg" 7 40 >"$CURR_TTY" 2>&1
}

show_msg() {
  local msg="$1"
  dialog --title "Deduplicator $VERSION" --msgbox "$msg" 9 40 >"$CURR_TTY" 2>&1
}

yesno() {
  local msg="$1"
  dialog --title "Deduplicator $VERSION" --yesno "$msg" 9 40 >"$CURR_TTY" 2>&1
}

choose_disk() {
  local c
  c=$(dialog --title "Deduplicator $VERSION" --menu "Select SD card:" 10 30 3 \
    "roms"  "SD1 (/roms)" \
    "roms2" "SD2 (/roms2)" \
    "CANCEL" "Cancel" \
    --output-fd 1 2>"$CURR_TTY") || return 1
  [[ -z "$c" || "$c" == "CANCEL" ]] && return 1
  ROMROOT="/$c"
  return 0
}

view_log_file() {
  if [[ ! -f "$LOG_FILE" ]]; then
    show_msg "Deduplicator.log does not exist:\n/tools/Deduplicator.log"
    return
  fi

  # Show a wrapped copy of the log to avoid horizontal scrolling in dialog.
  local rows cols W H wrap_w tmp
  tmp="$(mktemp)"

  # Detect terminal size (fallback to 20x80).
  if read -r rows cols < <(stty size <"$CURR_TTY" 2>/dev/null); then
    H="$rows"
    W="$cols"
  else
    H=20
    W=80
  fi

  # Keep a safe margin for dialog borders/padding.
  wrap_w=$(( W - 6 ))
  (( wrap_w < 40 )) && wrap_w=40

  # Expand tabs and wrap long lines.
  if command -v expand >/dev/null 2>&1; then
    LC_ALL=C expand -t 4 -- "$LOG_FILE" | LC_ALL=C fold -s -w "$wrap_w" > "$tmp"
  else
    LC_ALL=C sed $'s/\t/    /g' "$LOG_FILE" | LC_ALL=C fold -s -w "$wrap_w" > "$tmp"
  fi

  dialog --title "Deduplicator.log" \
         --ok-label "EXIT" \
         --textbox "$tmp" "$H" "$W" \
         >"$CURR_TTY" 2>&1

  rm -f "$tmp" 2>/dev/null || true
}

###############################################################################
# LOGGING
###############################################################################
LOG_START_TS=0
LOG_TOTAL_FILES=0
LOG_DUP_COUNT=0
LOG_FREED_BYTES=0
LOG_BROKEN_ZIP_COUNT=0
LOG_BROKEN_ZIP_BYTES=0
# Global duplicate list and last scan root, so we can move duplicates later
declare -a DUP_LIST=()
LAST_DEDUP_ROOT=""
# Broken ZIP list captured during scan (unique paths only).
declare -a BROKEN_ZIP_LIST=()
declare -A BROKEN_ZIP_SEEN=()

init_log() {
  local root="$1" mode="$2"
  LOG_START_TS=$(date +%s)
  LOG_TOTAL_FILES=0
  LOG_DUP_COUNT=0
  LOG_FREED_BYTES=0
  LOG_BROKEN_ZIP_COUNT=0
  LOG_BROKEN_ZIP_BYTES=0
  # Empty MD5 outputs are ignored
  {
    echo "Deduplicator log"
    echo "Start: $(date)"
    echo "Root : $root"
    echo "Mode : $mode (PER = per emulator, ALL = across all emulators)"
    echo ""
    echo "__SUMMARY__"
    echo "Duplicates:"
    echo "----------"
  } > "$LOG_FILE"
}

log_dup() {
  local md5="$1" dup="$2" keep="$3"
  {
    echo "MD5 : $md5"
    echo "DUP : $dup"
    echo "KEEP: $keep"
    echo
  } >> "$LOG_FILE"
}

log_broken_zip() {
    local path="$1"
    local emu="$2"
	
	# Avoid double-counting/logging the same broken archive if detected in multiple stages.
    if [[ -n "${BROKEN_ZIP_SEEN[$path]:-}" ]]; then
        return
    fi
    BROKEN_ZIP_SEEN["$path"]=1
    BROKEN_ZIP_LIST+=("$path")
	
    local size

    size=$(stat -c %s -- "$path" 2>/dev/null || echo 0)

    ((LOG_BROKEN_ZIP_COUNT++))
    ((LOG_BROKEN_ZIP_BYTES += size))

    {
        echo "BROKEN_ZIP: $path"
        [[ -n "$emu" ]] && echo "EMU       : $emu"
        echo
    } >>"$LOG_FILE"
}

finalize_log() {
    local end_ts
    end_ts=$(date +%s)
    local elapsed=$((end_ts - LOG_START_TS))

    local freed="$LOG_FREED_BYTES"
    local freed_mb=$((freed / 1024 / 1024))

    local broken="$LOG_BROKEN_ZIP_COUNT"
    local broken_bytes="$LOG_BROKEN_ZIP_BYTES"
    local broken_mb=$((broken_bytes / 1024 / 1024))

  local sumtmp outtmp
  sumtmp="$(mktemp)"
  outtmp="$(mktemp)"

  {
    echo "Summary"
    echo "======="
    echo "Total files             : $LOG_TOTAL_FILES"
    echo "Duplicates              : $LOG_DUP_COUNT"
    echo "Freed space             : ${freed} bytes (~${freed_mb} MB)"
    echo "Broken archives (zip)   : $broken"
    echo "Broken archives size    : ${broken_bytes} bytes (~${broken_mb} MB)"
    echo "Elapsed time            : ${elapsed}s"
    echo
  } > "$sumtmp"

  awk -v sf="$sumtmp" '
    $0=="__SUMMARY__" {
      while ((getline l < sf) > 0) print l
      close(sf)
      next
    }
    { print }
  ' "$LOG_FILE" > "$outtmp" && mv "$outtmp" "$LOG_FILE"
  
  echo "----- END OF LOG FILE ($(date '+%Y-%m-%d %H:%M:%S')) -----" >> "$LOG_FILE"

  rm -f "$sumtmp" "$outtmp" 2>/dev/null || true
}

###############################################################################
# DEDUP ENGINE (keep oldest; duplicates = newer files)
###############################################################################
# Helper: get logical size and inner ROM path for a file (plain, ZIP).
# Output: "size<TAB>inner" to stdout; inner = "-" for non-archive files.
# For archives:
#   - we only accept archives that contain exactly one ROM file
#     with extension from EXT_MAP[emu].
#   - size is the uncompressed size of that ROM.
dedup_get_archive_rom_info() {
    local f="$1"
    local emu="$2"
    local __outvar="$3"
    local ext="${f##*.}"
    ext="${ext,,}"

    local allowed_exts="${EXT_MAP[$emu]}"
    [[ -z "$allowed_exts" ]] && return 1

    local -a inner_list=()

    case "$ext" in
        zip)
            local zip_list
                        zip_list=$(unzip -Z1 -- "$f" 2>/dev/null) || {
    log_broken_zip "$f" "$emu"
    return 1
}
[[ -z "$zip_list" ]] && { log_broken_zip "$f" "$emu"; return 1; }

            local z zext e
            while IFS= read -r z; do
                [[ "$z" == */ ]] && continue
                zext="${z##*.}"
                zext="${zext,,}"
                for e in $allowed_exts; do
                    if [[ "$zext" == "$e" ]]; then
                        inner_list+=("$z")
                        break
                    fi
                done
            done <<< "$zip_list"
            ;;
        *)
            return 1
            ;;
    esac

    # The archive must have exactly one ROM file inside
    (( ${#inner_list[@]} == 1 )) || return 1

      # Return the chosen inner ROM path via an output variable to avoid subshell side effects.
    printf -v "$__outvar" '%s' "${inner_list[0]}"
    return 0
}
dedup_unzip_escape_pattern() {
  local s="$1"
  # Escape glob metacharacters for Info-ZIP pattern matching
  s="${s//\\/\\\\}"
  s="${s//[/\\[}"
  s="${s//]/\\]}"
  s="${s//\*/\\*}"
  s="${s//\?/\\?}"
  printf '%s' "$s"
}

# Helper: compute MD5 of logical ROM content.
# - For plain files (inner="-"): md5sum of file on disk.
# - For ZIP md5sum of inner ROM stream.
dedup_compute_md5_logical() {
  local f="$1" emu="$2" inner="$3" __outvar="$4"
  local ext="${f##*.}"
  ext="${ext,,}"

  # MD5 of an empty stream (empty outputs are ignored).
  local EMPTY_MD5_HASH="d41d8cd98f00b204e9800998ecf8427e"

  if [[ "$inner" == "-" ]]; then
    local v
    v=$(md5sum "$f" 2>/dev/null | awk '{print $1}')
    [[ -z "$v" ]] && return 1
		if [[ "$v" == "$EMPTY_MD5_HASH" ]]; then
		  return 1
		fi
    printf -v "$__outvar" '%s' "$v"
    return 0
  fi

  case "$ext" in
    zip)
      local size sz v rc
      size=$(stat -c %s -- "$f" 2>/dev/null || echo 0)

      set -o pipefail
      local inner_pat
inner_pat="$(dedup_unzip_escape_pattern "$inner")"
      sz=$(unzip -p -- "$f" "$inner_pat" 2>/dev/null | wc -c | awk '{print $1}')
      rc=$?
      set +o pipefail
      [[ -z "$sz" ]] && sz=0

      if (( rc != 0 )); then
        log_broken_zip "$f" "$emu"
        return 1
      fi

	  if (( size > 0 && sz == 0 )); then
	    return 1
	  fi

      set -o pipefail
      v=$(unzip -p -- "$f" "$inner_pat" 2>/dev/null | md5sum | awk '{print $1}')
      rc=$?
      set +o pipefail

      if [[ $rc -ne 0 || -z "$v" ]]; then
        log_broken_zip "$f" "$emu"
        return 1
      fi

	  if [[ "$v" == "$EMPTY_MD5_HASH" ]]; then
	    return 1
	  fi

      printf -v "$__outvar" '%s' "$v"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

dedup_scan() {
  local ROOT="$1"
  local MODE="$2"  # "PER" or "ALL"

  DUP_LIST=()
  LAST_DEDUP_ROOT="$ROOT"
  BROKEN_ZIP_LIST=()
  BROKEN_ZIP_SEEN=()

  init_log "$ROOT" "$MODE"

  # ---------------------------------------------------------------------------
  # Stage 1/3: collect ROM candidates (cheap filter)
  # ---------------------------------------------------------------------------
  local -a C_PATH C_EMU C_FSIZE C_MTIME C_IS_ARCHIVE C_INNER C_MD5 C_VALID

  local TOTAL_CAND=0

  exec 3> >(
    dialog --title "Deduplicator $VERSION" \
           --progressbox 3 40 \
           >"$CURR_TTY" 2>&1
  )

  printf 'Stage 1/3: collecting ROM candidates (filter by emulator and extension)...\n' >&3

  while IFS= read -r -d '' f; do
    local rel="${f#$ROOT/}"
    local emu="${rel%%/*}"
    [[ -z "$emu" || "$emu" == "$rel" ]] && continue

    # Respect EMU_FILTER if set
    if [[ -n "$EMU_FILTER" && "$emu" != "$EMU_FILTER" ]]; then
      continue
    fi

    # Skip ignored root directories and emulators without EXT_MAP entry
    is_ignored_dir "$emu" && continue
    [[ -z "${EXT_MAP[$emu]:-}" ]] && continue

    # Check extension is allowed for this emulator
    local ext="${f##*.}"; ext="${ext,,}"
    local ok=0 e
    for e in ${EXT_MAP[$emu]}; do
      [[ "$ext" == "$e" ]] && ok=1 && break
    done
    (( ok == 1 )) || continue

    C_PATH[TOTAL_CAND]="$f"
    C_EMU[TOTAL_CAND]="$emu"
    C_VALID[TOTAL_CAND]=1

    ((TOTAL_CAND++))
    printf 'Stage 1/3: candidates found... %d\n' "$TOTAL_CAND" >&3
  done < <(
    find "$ROOT" -type f \
      ! -path "*/images/*" \
      ! -path "*/videos/*" \
      -print0 2>/dev/null || true
  )

  printf 'Stage 1/3: total ROM candidates... %d\n' "$TOTAL_CAND" >&3
  exec 3>&-

if (( TOTAL_CAND == 0 )); then
  # Replace Summary anchor (if present) so the log does not look truncated.
  if [[ -f "$LOG_FILE" ]]; then
    if grep -q '^_SUMMARY_$' "$LOG_FILE"; then
      sed -i 's/^_SUMMARY_$/No ROM files were found./' "$LOG_FILE"
    elif grep -q '^__SUMMARY__$' "$LOG_FILE"; then
      sed -i 's/^__SUMMARY__$/No ROM files were found./' "$LOG_FILE"
    else
      # Fallback for builds without an anchor: insert a note right after the Mode line.
      awk '
        BEGIN{ins=0}
        {print}
        ins==0 && $0 ~ /^Mode[[:space:]]*:/ {
          print "No ROM files were found."
          ins=1
        }
      ' "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
  fi

  show_msg "No ROM files found to scan on $ROOT."
  return
fi


  if ! yesno "Done. Found $TOTAL_CAND ROM candidates.\n\nStart searching for duplicates now?"; then
      # Replace Summary anchor (if present) so the log does not look truncated.
     if [[ -f "$LOG_FILE" ]]; then
        if grep -q '^_SUMMARY_$' "$LOG_FILE"; then
          sed -i 's/^_SUMMARY_$/No ROM files were scanned yet./' "$LOG_FILE"
        elif grep -q '^__SUMMARY__$' "$LOG_FILE"; then
          sed -i 's/^__SUMMARY__$/No ROM files were scanned yet./' "$LOG_FILE"
        else
          # Fallback for builds without an anchor: insert a note right after the Mode line.
          awk '
            BEGIN{ins=0}
            {print}
            ins==0 && $0 ~ /^Mode[[:space:]]*:/ {
              print "No ROM files were scanned yet."
              ins=1
            }
          ' "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        fi
    fi
    return
  fi

  LOG_TOTAL_FILES=$TOTAL_CAND

    # ---------------------------------------------------------------------------
    # Stage 2/3: preparing metadata (physical size / mtime, archive inner file)
    # ---------------------------------------------------------------------------
    local TOTAL_META=$TOTAL_CAND
    local COUNT_META=0
    local LAST_META_PCT_X100=-1  # last progress in hundredths of percent (0..10000)


    exec 3> >(
      dialog --gauge "Stage 2/3: reading metadata..." 9 60 0 2>"$CURR_TTY"
    )

    {
      echo "XXX"
      echo "0"
      echo "Stage 2/3: reading metadata: 0.00% (0 / $TOTAL_META)\n\n..."
      echo "XXX"
    } >&3

    local i path emu ext
    local file_size mtime inner

    for (( i=0; i<TOTAL_CAND; i++ )); do
 
        (( ${C_VALID[i]:-0} == 1 )) || continue

        path="${C_PATH[i]}"
        emu="${C_EMU[i]}"

        file_size=$(stat -c %s -- "$path" 2>/dev/null || echo 0)
        mtime=$(stat -c %Y -- "$path" 2>/dev/null || echo 0)

        C_FSIZE[i]="$file_size"
        C_MTIME[i]="$mtime"
        C_IS_ARCHIVE[i]=0
        C_INNER[i]=""

        ext="${path##*.}"
        ext="${ext,,}"

        if [[ "$ext" == "zip" ]]; then
            # Arhive: we are trying to fing exactly one ROM inside
            C_IS_ARCHIVE[i]=1
            if [[ -n "${EXT_MAP[$emu]:-}" ]]; then
              inner=""
                if ! dedup_get_archive_rom_info "$path" "$emu" inner; then
                    # No ROM inside / multiple ROMs inside / can't read archive — exclude
                    C_VALID[i]=0
                    C_IS_ARCHIVE[i]=0
                    C_INNER[i]=""
                    continue
                fi
                C_INNER[i]="$inner"
            fi
        fi
        ((COUNT_META++))
local pct_x100=$(( COUNT_META * 10000 / TOTAL_META ))
(( pct_x100 > 10000 )) && pct_x100=10000

if (( pct_x100 != LAST_META_PCT_X100 )); then
  LAST_META_PCT_X100=$pct_x100

  local pct_int=$(( pct_x100 / 100 ))
  local pct_frac=$(( pct_x100 % 100 ))
  local pct_str
  printf -v pct_str "%d.%02d" "$pct_int" "$pct_frac"
  
  local fname
  fname="${path##*/}"

  {
    echo "XXX"
    echo "$pct_int"  # dialog gauge value must be integer 0..100
    echo "Stage 2/3: reading metadata: ${pct_str}% (${COUNT_META} / ${TOTAL_META})\n\n${fname}"
    echo "XXX"
  } >&3
fi
    done

        {
      echo "XXX"
      echo "100"
      echo "Stage 2/3: reading metadata: 100.00% (${COUNT_META} / ${TOTAL_META})\n\nCompleted."
      echo "XXX"
    } >&3
    exec 3>&-

    # ---------------------------------------------------------------------------
    # Stage 3/3: computing MD5 hashes
    # ---------------------------------------------------------------------------
  local TOTAL_MD5=0
    for (( i=0; i<TOTAL_CAND; i++ )); do
        (( ${C_VALID[i]:-0} == 1 )) && (( TOTAL_MD5++ ))
    done
    (( TOTAL_MD5 < 1 )) && TOTAL_MD5=1  # to avoid division by zero

  local COUNT_MD5=0
  local LAST_MD5_PCT_X100=-1  # last progress in hundredths of percent (0..10000)

  exec 3> >(
    dialog --gauge "Stage 3/3: computing MD5..." 9 60 0 2>"$CURR_TTY"
  )

  {
    echo "XXX"
    echo "0"
    echo "Stage 3/3: computing MD5: 0.00% (0 / $TOTAL_MD5)\n\n..."
    echo "XXX"
  } >&3
  
  local md5
  for (( i=0; i<TOTAL_CAND; i++ )); do
    (( ${C_VALID[i]:-0} == 1 )) || continue

    path="${C_PATH[i]}"
    emu="${C_EMU[i]}"
    md5=""
	if ! dedup_compute_md5_logical "$path" "$emu" "${C_INNER[i]:--}" md5; then
	  C_VALID[i]=0
	  continue
	fi
	[[ -z "$md5" ]] && { C_VALID[i]=0; continue; }

    C_MD5[i]="$md5"

    ((COUNT_MD5++))
    local pct_x100=$(( COUNT_MD5 * 10000 / TOTAL_MD5 ))
(( pct_x100 > 10000 )) && pct_x100=10000

if (( pct_x100 != LAST_MD5_PCT_X100 )); then
  LAST_MD5_PCT_X100=$pct_x100

  local pct_int=$(( pct_x100 / 100 ))
  local pct_frac=$(( pct_x100 % 100 ))
  local pct_str
  printf -v pct_str "%d.%02d" "$pct_int" "$pct_frac"
  
  local fname
  fname="${path##*/}"

  {
    echo "XXX"
    echo "$pct_int"
    echo "Stage 3/3: computing MD5: ${pct_str}% (${COUNT_MD5} / ${TOTAL_MD5})\n\n${fname}"
    echo "XXX"
  } >&3
fi

  done

  {
    echo "XXX"
    echo "100"
    echo "Stage 3/3: computing MD5 for candidate files: 100.00% ($COUNT_MD5 / $TOTAL_MD5)\n\nCompleted."
    echo "XXX"
  } >&3
  exec 3>&-

  # ---------------------------------------------------------------------------
  # Final step: analyze MD5 groups and mark duplicates (empty MD5 candidates are ignored in Stage 3).
  # ---------------------------------------------------------------------------
  declare -A GROUP_MEMBERS GROUP_OLDEST

    # Build MD5 groups (group by MD5, in the PER mode by emulator too).
    #
    # Key format:
    #   MODE=PER: "<emu>::<md5>"
    #   MODE=ALL: "<md5>"
  for (( i=0; i<TOTAL_CAND; i++ )); do
    (( ${C_VALID[i]:-0} == 1 )) || continue
    md5="${C_MD5[i]:-}"
    [[ -z "$md5" ]] && continue

    emu="${C_EMU[i]}"

    if [[ "$MODE" == "PER" ]]; then
		key="${emu}::${md5}"
	else
		key="$md5"
	fi

    GROUP_MEMBERS["$key"]="${GROUP_MEMBERS[$key]} $i"

    local old="${GROUP_OLDEST[$key]:--1}"
    if [[ "$old" == "-1" ]]; then
      GROUP_OLDEST["$key"]="$i"
    else
      local old_mtime="${C_MTIME[old]:-0}"
      local cur_mtime="${C_MTIME[i]:-0}"
      if (( cur_mtime < old_mtime )); then
        GROUP_OLDEST["$key"]="$i"
      fi
    fi
  done

  # Process groups
  local g members base_idx idx md5_val
  for g in "${!GROUP_MEMBERS[@]}"; do
    members=(${GROUP_MEMBERS[$g]})
    (( ${#members[@]} < 2 )) && continue

    # key format:
    # PER: "<emu>::<md5>"
    # ALL: "<md5>"
    md5_val="${g##*::}"

    base_idx="${GROUP_OLDEST[$g]}"
    local base_path="${C_PATH[base_idx]}"
    local base_inner="${C_INNER[base_idx]:--}"

    for idx in "${members[@]}"; do
      (( idx == base_idx )) && continue

      path="${C_PATH[idx]}"

      # Mark as duplicate (same MD5 within the selected mode).
      DUP_LIST+=("$path")
      ((LOG_DUP_COUNT++))
      local fsize="${C_FSIZE[idx]:-0}"
      ((LOG_FREED_BYTES += fsize))
      log_dup "$md5_val" "$path" "$base_path"
    done
  done

  finalize_log
  show_msg "Duplicate scan completed.\n\nDetails about found duplicates are in:\n$ROOT/tools/Deduplicator.log"

  # Move duplicates (only if any were found)
  if (( ${#DUP_LIST[@]} > 0 )); then
    move_duplicates_to_dedupbin "$ROOT"
  fi

  # Then offer moving broken ZIPs (only if any were found).
  # This will be shown even if user declined moving duplicates.
  if (( ${#BROKEN_ZIP_LIST[@]} > 0 )); then
    move_broken_zips_to_dedupbin "$ROOT"
  fi

}

###############################################################################
# MOVE DUPLICATES TO DEDUPBIN (reused by dedup_scan and main menu)
###############################################################################
move_duplicates_to_dedupbin() {
  local ROOT="$1"

		  # If no root passed, try to use last scan root
		  if [[ -z "$ROOT" ]]; then
			ROOT="$LAST_DEDUP_ROOT"
		  fi

  # If no duplicates in memory, inform user and abort
  if (( ${#DUP_LIST[@]} == 0 )); then
    show_msg "No duplicates found to move to DedupBin.\n\n Please, rerun the deduplication process from the beginning."
    return
  fi

  # Confirm move
  if ! yesno "Move ${#DUP_LIST[@]} duplicate files to DedupBin?\n\nThey will NOT be deleted, only moved.\n\nYou can do it later from the main menu."; then
    return
  fi

  local ROOT_NAME="${ROOT##*/}"
  local TARGET="$ROOT/DedupBin/$ROOT_NAME"
  mkdir -p "$TARGET"

  local TOTAL_MOVE=${#DUP_LIST[@]}
  local MOVE_COUNT=0
  local STEP_MOVE=$(( TOTAL_MOVE / 1 )) #adjust denominator to change the refresh frequency
  (( STEP_MOVE < 1 )) && STEP_MOVE=1

  exec 3> >(
    dialog --title "Deduplicator $VERSION" \
           --progressbox 3 40 \
           >"$CURR_TTY" 2>&1
  )
  printf 'Moving duplicates to DedupBin...\n' >&3

  for f in "${DUP_LIST[@]}"; do
    ((MOVE_COUNT++))
    local rel2="${f#$ROOT}"
    local dest="$TARGET$rel2"
    mkdir -p "$(dirname "$dest")"
    mv "$f" "$dest"
    if (( MOVE_COUNT % STEP_MOVE == 0 || MOVE_COUNT == TOTAL_MOVE )); then
      printf 'Moved duplicates: %d / %d\n' "$MOVE_COUNT" "$TOTAL_MOVE" >&3
    fi
  done
  
  exec 3>&-

  show_msg "Duplicates moved to:\n$TARGET"

  # Clear duplicate list to avoid moving same files again
  DUP_LIST=()
}

move_broken_zips_to_dedupbin() {
  local ROOT="$1"

  # If no root passed, try to use last scan root
  if [[ -z "$ROOT" ]]; then
    ROOT="$LAST_DEDUP_ROOT"
  fi

  # If no broken zips in memory, do nothing (no dialogs)
  if (( ${#BROKEN_ZIP_LIST[@]} == 0 )); then
    return
  fi

  # Confirm move
  if ! yesno "Move ${#BROKEN_ZIP_LIST[@]} broken ZIP files to DedupBin?\n\nThey will NOT be deleted, only moved.\n\nYou can restore them later from the main menu."; then
    return
  fi

  local ROOT_NAME="${ROOT##*/}"
  local TARGET="$ROOT/DedupBin/$ROOT_NAME"
  mkdir -p "$TARGET"

  local TOTAL_MOVE=${#BROKEN_ZIP_LIST[@]}
  local MOVE_COUNT=0
  local STEP_MOVE=$(( TOTAL_MOVE / 1 )) #adjust denominator to change the refresh frequency
  (( STEP_MOVE < 1 )) && STEP_MOVE=1
  
  exec 3> >(
    dialog --title "Deduplicator $VERSION" \
           --progressbox 3 40 \
           >"$CURR_TTY" 2>&1
  )
  printf 'Moving broken ZIP files to DedupBin...\n' >&3

  for f in "${BROKEN_ZIP_LIST[@]}"; do
    ((MOVE_COUNT++))

    # Skip if file no longer exists (e.g., already moved manually)
    [[ -e "$f" ]] || continue

    local rel2="${f#$ROOT}"
    local dest="$TARGET$rel2"
    mkdir -p "$(dirname "$dest")"
    mv "$f" "$dest"

    if (( MOVE_COUNT % STEP_MOVE == 0 || MOVE_COUNT == TOTAL_MOVE )); then
      printf 'Moved broken ZIP files: %d / %d\n' "$MOVE_COUNT" "$TOTAL_MOVE" >&3
    fi
  done
  
  exec 3>&-

  show_msg "Broken ZIP files moved to:\n$TARGET"

  # Clear list to avoid moving same files again
  BROKEN_ZIP_LIST=()
  BROKEN_ZIP_SEEN=()
}

###############################################################################
# MEDIA CLEANUP (images/videos with -image/-video, subfolders supported)
###############################################################################
cleanup_media() {
  local ROOT="$1"

  declare -A ROMS    # key "emu:basename" lowercased
  declare -A IMG_CNT
  declare -A VID_CNT
  declare -a ORPHAN
  ORPHAN=()
  
  stop_gptokeyb #temporary disable keyboard
  
  show_info "Collecting ROM names for media cleanup...\n\nPlease wait."

  # 1) collect ROM basenames
  for emu_dir in "$ROOT"/*; do
    [[ -d "$emu_dir" ]] || continue
    local emu
    emu="$(basename "$emu_dir")"
    is_ignored_dir "$emu" && continue
    [[ -z "${EXT_MAP[$emu]:-}" ]] && continue

    while IFS= read -r -d '' r; do
      local ext="${r##*.}"; ext="${ext,,}"
      local ok=0
      for e in ${EXT_MAP[$emu]}; do
        [[ "$ext" == "$e" ]] && ok=1 && break
      done
      (( ok == 1 )) || continue

      local base="${r##*/}"
      base="${base%.*}"
      base="${base,,}"
      ROMS["$emu:$base"]=1
    done < <(
      find "$emu_dir" -type f \
        ! -path "*/images/*" \
        ! -path "*/videos/*" \
        -print0 2>/dev/null || true
    )
  done
  
  # 2) scan all media files (images & videos)
  show_info "Scanning media files (images/videos)...\n\nPlease wait."

  for emu_dir in "$ROOT"/*; do
    [[ -d "$emu_dir" ]] || continue
    local emu
    emu="$(basename "$emu_dir")"
    is_ignored_dir "$emu" && continue
    [[ -z "${EXT_MAP[$emu]:-}" ]] && continue

    # images
    while IFS= read -r -d '' img; do
      [[ -f "$img" ]] || continue
      local b
      b="$(basename "$img")"
      b="${b%-image*}"
      b="${b,,}"
      if [[ -z "${ROMS["$emu:$b"]:-}" ]]; then
        ORPHAN+=("$img")
        ((IMG_CNT[$emu]++))
      fi
    done < <(
      find "$emu_dir" -type f -path "*/images/*-image.*" -print0 2>/dev/null || true
    )

    # videos
    while IFS= read -r -d '' vid; do
      [[ -f "$vid" ]] || continue
      local b
      b="$(basename "$vid")"
      b="${b%-video*}"
      b="${b,,}"
      if [[ -z "${ROMS["$emu:$b"]:-}" ]]; then
        ORPHAN+=("$vid")
        ((VID_CNT[$emu]++))
      fi
    done < <(
      find "$emu_dir" -type f -path "*/videos/*-video.*" -print0 2>/dev/null || true
    )
	# downloaded_images (no suffix, name matches ROM basename; respect emulator subfolders)
    local di_dir="$emu_dir/downloaded_images"
    if [[ -d "$di_dir" ]]; then
      # 2.1) handle subfolders in downloaded_images that do NOT exist as subfolders in emulator root
      local -a BAD_IMG_SUBDIRS=()
      local subdir subname
      for subdir in "$di_dir"/*; do
        [[ -d "$subdir" ]] || continue
        subname="$(basename "$subdir")"

        # Skip default_images folder completely (do not treat as bad and do not collect its files)
        if [[ "$subname" == "default_images" ]]; then
          continue
        fi

        # if emulator does not have a matching subfolder, treat whole downloaded_images/<subname> as orphan
        if [[ ! -d "$emu_dir/$subname" ]]; then
          BAD_IMG_SUBDIRS+=("$subdir")
          while IFS= read -r -d '' img; do
            [[ -f "$img" ]] || continue
            ORPHAN+=("$img")
            ((IMG_CNT[$emu]++))
          done < <(find "$subdir" -type f -print0)
        fi
      done

      # 2.2) scan all remaining files under downloaded_images that are not in bad subfolders
      while IFS= read -r -d '' img; do
        [[ -f "$img" ]] || continue

        # Skip any files inside downloaded_images/default_images
        case "$img" in
          "$di_dir/default_images"/*) continue ;;
        esac

        # skip files in bad subdirs (already marked as orphan above)
        local skip=0
        local bad
        for bad in "${BAD_IMG_SUBDIRS[@]}"; do
          case "$img" in
            "$bad"/*) skip=1; break ;;
          esac
        done
        (( skip == 1 )) && continue

        # For downloaded_images, filename (without extension) fully matches ROM filename.
        local b
        b="$(basename "$img")"
        b="${b%.*}"
        b="${b,,}"

        if [[ -z "${ROMS["$emu:$b"]:-}" ]]; then
          ORPHAN+=("$img")
          ((IMG_CNT[$emu]++))
        fi
      done < <(find "$di_dir" -type f -print0)
    fi
	 # downloaded_videos (no suffix, name matches ROM basename; respect emulator subfolders)
    local dv_dir="$emu_dir/downloaded_videos"
    if [[ -d "$dv_dir" ]]; then
      # 2.3) handle subfolders in downloaded_videos that do NOT exist as subfolders in emulator root
      local -a BAD_VID_SUBDIRS=()
      local vsubdir vsubname
      for vsubdir in "$dv_dir"/*; do
        [[ -d "$vsubdir" ]] || continue
        vsubname="$(basename "$vsubdir")"
        if [[ ! -d "$emu_dir/$vsubname" ]]; then
          BAD_VID_SUBDIRS+=("$vsubdir")
          while IFS= read -r -d '' vid; do
            [[ -f "$vid" ]] || continue
            ORPHAN+=("$vid")
            ((VID_CNT[$emu]++))
          done < <(find "$vsubdir" -type f -print0)
        fi
      done

      # 2.4) scan all remaining files under downloaded_videos that are not in bad subfolders
      while IFS= read -r -d '' vid; do
        [[ -f "$vid" ]] || continue

        # skip files in bad subdirs (already marked as orphan above)
        local skip=0
        local badv
        for badv in "${BAD_VID_SUBDIRS[@]}"; do
          case "$vid" in
            "$badv"/*) skip=1; break ;;
          esac
        done
        (( skip == 1 )) && continue

        local b
        b="$(basename "$vid")"
        b="${b%.*}"
        b="${b,,}"

        if [[ -z "${ROMS["$emu:$b"]:-}" ]]; then
          ORPHAN+=("$vid")
          ((VID_CNT[$emu]++))
        fi
      done < <(find "$dv_dir" -type f -print0)
    fi
  done
  
  start_gptokeyb #re-enable keyboard
  
  if (( ${#ORPHAN[@]} == 0 )); then
    show_msg "No orphaned media files found."
    return
  fi

  if ! yesno "Found ${#ORPHAN[@]} orphaned media files.\n\nMove them to DedupBin?"; then
    return
  fi

  local ROOT_NAME="${ROOT##*/}"
  local TARGET="$ROOT/DedupBin/$ROOT_NAME"
  mkdir -p "$TARGET"

  local TOTAL=${#ORPHAN[@]}
  local COUNT=0
  local STEP=$(( TOTAL / 1 )) #adjust denominator to change the refresh frequency
  (( STEP < 1 )) && STEP=1
  
  exec 3> >(
    dialog --title "Deduplicator $VERSION" \
           --progressbox 3 40 \
           >"$CURR_TTY" 2>&1
  )
  printf 'Cleaning orphaned media...\n' >&3

  for f in "${ORPHAN[@]}"; do
    ((COUNT++))
    local rel="${f#$ROOT}"
    local dest="$TARGET$rel"
    mkdir -p "$(dirname "$dest")"
    mv "$f" "$dest"
    if (( COUNT % STEP == 0 || COUNT == TOTAL )); then
      printf 'Moved orphaned media: %d / %d\n' "$COUNT" "$TOTAL" >&3
    fi
  done
  
  exec 3>&-

  local REPORT=""
  for emu in "${!IMG_CNT[@]}"; do
    REPORT+="$emu:\n  Images moved to DedupBin: ${IMG_CNT[$emu]:-0}\n  Videos moved to DedupBin: ${VID_CNT[$emu]:-0}\n\n"
  done

  show_msg "Media cleanup completed.\n\n$REPORT"
}

###############################################################################
# RESTORE FROM DEDUPBIN
###############################################################################
restore_from_dedupbin() {
  local ROOT="$1"
  local RB="$ROOT/DedupBin"

  if [[ ! -d "$RB" ]]; then
    show_msg "DedupBin not found on $ROOT."
    return
  fi

  local TOTAL=0
  local TOTAL_BYTES=0
  
  stop_gptokeyb #temporary disable keyboard
  
  show_info "Scanning DedupBin...\n\nPlease wait."

  while IFS= read -r -d '' f; do
    ((TOTAL++))
    local sz
    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    ((TOTAL_BYTES += sz))
  done < <(find "$RB" -type f -print0 2>/dev/null || true)
  
  start_gptokeyb #re-enable keyboard
  
  if (( TOTAL == 0 )); then
    show_msg "DedupBin is empty on $ROOT."
    return
  fi

  local MB=$(( TOTAL_BYTES / 1024 / 1024 ))
  if ! yesno "DedupBin on $ROOT contains:\n\nFiles : $TOTAL\nSize  : ${TOTAL_BYTES} bytes (~${MB} MB)\n\nRestore all files?\nExisting files in ROM folders will be kept (no overwrite)."; then
    return
  fi

  local COUNT=0
  local STEP=$(( TOTAL / 1 )) #adjust denominator to change the refresh frequency
  (( STEP < 1 )) && STEP=1
  local RESTORED=0 SKIPPED=0 ERRORS=0
  
  exec 3> >(
    dialog --title "Deduplicator $VERSION" \
           --progressbox 3 40 \
           >"$CURR_TTY" 2>&1
  )
  printf 'Restoring from DedupBin...\n' >&3

  while IFS= read -r -d '' f; do
    ((COUNT++))
    local rel_ts="${f#$RB/}"   # "<ts>/emu/..."
    local rel="${rel_ts#*/}"   # "emu/..."
    local dest="$ROOT/$rel"

    if [[ -e "$dest" ]]; then
      ((SKIPPED++))
    else
      mkdir -p "$(dirname "$dest")"
      if mv "$f" "$dest" 2>/dev/null; then
        ((RESTORED++))
      else
        ((ERRORS++))
      fi
    fi

    if (( COUNT % STEP == 0 || COUNT == TOTAL )); then
      printf 'Restored from DedupBin: %d / %d\n' "$COUNT" "$TOTAL" >&3
    fi
  done < <(find "$RB" -type f -print0 2>/dev/null || true)
  
  exec 3>&-

  # Remove empty directories inside DedupBin (timestamps, emulator folders, etc.)
  find "$RB" -depth -type d ! -path "$RB" -exec rmdir {} + 2>/dev/null || true

  show_msg "Restore completed.\n\nRestored : $RESTORED\nSkipped  : $SKIPPED\nErrors   : $ERRORS"
}

###############################################################################
# DELETE Deduplicator.log
###############################################################################
delete_log_file() {
  if [[ -f "$LOG_FILE" ]]; then
    rm -f "$LOG_FILE"
    show_msg "Deduplicator.log has been deleted:\n/tools/Deduplicator.log"
  else
    show_msg "Deduplicator.log does not exist:\n/tools/Deduplicator.log"
  fi
}

###############################################################################
# DELETE DedupBin (PERMANENT)
###############################################################################
purge_dedupbin() {
  local ROOT="$1"
  local RB="$ROOT/DedupBin"

  if [[ ! -d "$RB" ]]; then
    show_msg "DedupBin does not exist on $ROOT."
    return
  fi
  
  stop_gptokeyb #temporary disable keyboard
  
  show_info "Calculating files count and size in DedupBin...\n\nPlease wait."

  local TOTAL=0 TOTAL_BYTES=0
  while IFS= read -r -d '' f; do
    ((TOTAL++))
    local sz
    sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
    ((TOTAL_BYTES += sz))
  done < <(find "$RB" -type f -print0 2>/dev/null || true)

  start_gptokeyb #re-enable keyboard

  if (( TOTAL == 0 )); then
    if yesno "DedupBin on $ROOT is already empty.\n\nDelete empty DedupBin folder anyway?"; then
      rm -rf "$RB"
      show_msg "DedupBin folder removed."
    fi
    return
  fi

  local MB=$(( TOTAL_BYTES / 1024 / 1024 ))
  if ! yesno "DedupBin on $ROOT contains:\n\nFiles : $TOTAL\nSize  : ${TOTAL_BYTES} bytes (~${MB} MB)\n\nPERMANENTLY delete all these files?\nThis cannot be undone."; then
    return
  fi

  rm -rf "$RB"
  show_msg "DedupBin deleted.\n\nDeleted files: $TOTAL\nFreed space  : ${TOTAL_BYTES} bytes (~${MB} MB)"
}

###############################################################################
# MAIN MENU LOOP
###############################################################################
TopMenu() {
  while true; do
    local CHOICE
	CHOICE=$(dialog --output-fd 1 \
      --title "Deduplicator $VERSION" \
      --menu "Choose action:" 14 70 9\
      1 "Deduplicate ROMs" \
      2 "Move duplicates / broken ZIP to DedupBin" \
      3 "View Deduplicator.log" \
      4 "Move orphaned images/videos to DedupBin" \
      5 "Restore from DedupBin" \
      6 "Delete Deduplicator.log" \
      7 "Delete DedupBin (permanently)" \
      X "Exit" \
      2>"$CURR_TTY") || cleanup_exit

    case "$CHOICE" in
      1)
        if ! choose_disk; then
          continue
        fi
        local MODE
        MODE=$(dialog --title "Deduplicator $VERSION" --menu "Deduplication mode:" 8 70 2 \
          "PER" "Per emulator (only within same emulator)" \
          "ALL" "Across all emulators together" \
          --output-fd 1 2>"$CURR_TTY") || continue
        [[ -z "$MODE" ]] && continue
		
		#Reset Emulator Filter
		EMU_FILTER=""
		
		if [[ "$MODE" == "PER" ]] && ! select_emulator_filter; then
			# User pressed Cancel -> back to main menu
			continue
		fi

        dedup_scan "$ROMROOT" "$MODE"
        ;;
      2)
        # Move results from the last deduplication run (if any).
        local moved_any=0

        if (( ${#DUP_LIST[@]} > 0 )); then
          move_duplicates_to_dedupbin ""
          moved_any=1
        fi

        if (( ${#BROKEN_ZIP_LIST[@]} > 0 )); then
          move_broken_zips_to_dedupbin ""
          moved_any=1
        fi

        if (( moved_any == 0 )); then
          show_msg "No duplicates or broken ZIP files found to move to DedupBin.\n\nPlease rerun the scan from the beginning."
        fi
        ;;
      3)
        view_log_file
        ;;
      4)
        if ! choose_disk; then
          continue
        fi
        cleanup_media "$ROMROOT"
        ;;
      5)
        if ! choose_disk; then
          continue
        fi
        restore_from_dedupbin "$ROMROOT"
        ;;
      6)
        delete_log_file
        ;;
      7)
        if ! choose_disk; then
          continue
        fi
        purge_dedupbin "$ROMROOT"
        ;;
      X|"")
        cleanup_exit
        ;;
      *)
        cleanup_exit
        ;;
    esac
  done
}

###############################################################################
# START
###############################################################################
start_gptokeyb
printf "\033c" > "$CURR_TTY"
TopMenu
