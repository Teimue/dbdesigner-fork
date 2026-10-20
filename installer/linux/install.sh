#!/bin/sh
# Installs DBDesigner Fork on Linux - the counterpart of the setup program
# for Windows (installer/DBDesignerFork.iss). Run it from the unpacked
# package (installer/linux/make-package.sh makes it):
#
#   ./install.sh                for the current user, below ~/.local
#   sudo ./install.sh           for all users, below /opt and /usr/local
#
# Options:
#   --user / --system           choose the kind of installation yourself
#   --prefix DIR                the program goes to DIR/dbdesigner-fork
#   --register-claude-code      register the MCP server in Claude Code
#   --register-claude-desktop   register the MCP server in Claude Desktop
#   --help
#
# It installs the program, the plugins, the MCP server, Data, Gfx and Doc
# into one directory (the program looks for them next to itself), the
# commands dbdesigner-fork and dbdesigner-fork-mcp, an entry in the
# application menu, and the examples into the documents of the user
# (DBDesigner, only files that are not there yet). An installation over an
# earlier one replaces the program; the settings (~/.DBDesigner-Fork) and the
# examples are kept. <program directory>/uninstall.sh removes it again.
set -eu

PKG=$(cd "$(dirname "$0")" && pwd)
SRC="$PKG/app"
[ -x "$SRC/DBDesignerFork" ] || { echo "No program in $SRC - run install.sh from the unpacked package." >&2; exit 1; }
VERSION=$(cat "$SRC/VERSION" 2>/dev/null || echo "?")

MODE=""
PREFIX=""
REG_CODE=no
REG_DESKTOP=no
while [ $# -gt 0 ]; do
  case "$1" in
    --user) MODE=user ;;
    --system) MODE=system ;;
    --prefix) shift; PREFIX=${1:?--prefix needs a directory} ;;
    --prefix=*) PREFIX=${1#--prefix=} ;;
    --register-claude-code) REG_CODE=yes ;;
    --register-claude-desktop) REG_DESKTOP=yes ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1 (--help)" >&2; exit 1 ;;
  esac
  shift
done

if [ -z "$MODE" ]; then
  if [ "$(id -u)" -eq 0 ]; then MODE=system; else MODE=user; fi
fi
if [ "$MODE" = system ] && [ "$(id -u)" -ne 0 ]; then
  echo "An installation for all users needs root: sudo $0 $*" >&2
  exit 1
fi

# The user who gets the examples and the MCP registration: with sudo the one
# who called it, as the Windows setup does for the registration
if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
  TARGET_USER=$SUDO_USER
  TARGET_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
  TARGET_USER=$(id -un)
  TARGET_HOME=$HOME
fi
as_target() {
  if [ "$(id -un)" = "$TARGET_USER" ]; then "$@"; else sudo -u "$TARGET_USER" -H "$@"; fi
}

if [ "$MODE" = system ]; then
  APPDIR="${PREFIX:-/opt}/dbdesigner-fork"
  BINDIR=/usr/local/bin
  DATADIR=/usr/local/share
else
  APPDIR="${PREFIX:-$HOME/.local/opt}/dbdesigner-fork"
  BINDIR="$HOME/.local/bin"
  DATADIR="${XDG_DATA_HOME:-$HOME/.local/share}"
fi
APPSDIR="$DATADIR/applications"
ICONDIR="$DATADIR/icons/hicolor/48x48/apps"

echo "DBDesigner Fork $VERSION"
echo "  for:      $([ "$MODE" = system ] && echo "all users" || echo "the user $TARGET_USER")"
echo "  program:  $APPDIR"
echo "  commands: $BINDIR/dbdesigner-fork, $BINDIR/dbdesigner-fork-mcp"
echo

# --- Libraries of the system ------------------------------------------------
LDCONFIG=$(command -v ldconfig || true)
[ -n "$LDCONFIG" ] || for f in /sbin/ldconfig /usr/sbin/ldconfig; do [ -x "$f" ] && LDCONFIG=$f; done
if [ -n "$LDCONFIG" ]; then
  has_lib() { "$LDCONFIG" -p 2>/dev/null | grep -q "[[:space:]]$1 "; }
else
  has_lib() { true; }   # cannot tell: do not stop the installation
fi
MISSING_REQUIRED=""
MISSING_OPTIONAL=""
has_lib libgtk-x11-2.0.so.0 || MISSING_REQUIRED="$MISSING_REQUIRED libgtk2.0-0"
has_lib libsqlite3.so.0 || MISSING_OPTIONAL="$MISSING_OPTIONAL libsqlite3-0(SQLite)"
{ has_lib libmysqlclient.so.24 || has_lib libmysqlclient.so.21; } || MISSING_OPTIONAL="$MISSING_OPTIONAL libmysqlclient24(MySQL)"
has_lib libfbclient.so.2 || MISSING_OPTIONAL="$MISSING_OPTIONAL libfbclient2(Firebird)"
if [ -n "$MISSING_REQUIRED" ]; then
  echo "The program needs GTK 2, which is not installed. On Debian / Ubuntu:" >&2
  echo "  sudo apt install$MISSING_REQUIRED" >&2
  exit 1
fi

# --- The program ------------------------------------------------------------
if [ -f "$APPDIR/DBDesignerFork" ]; then
  echo "Replacing the installation in $APPDIR"
  rm -rf "$APPDIR"
fi
mkdir -p "$APPDIR"
cp -R "$SRC/." "$APPDIR/"
rm -f "$APPDIR/dbdesigner-fork.desktop.in"
chmod 755 "$APPDIR/DBDesignerFork"
for f in "$APPDIR"/DBDplugin_* "$APPDIR/DBDesignerMCP"; do
  [ -f "$f" ] && chmod 755 "$f"
done
[ "$MODE" = system ] && chmod -R a+rX "$APPDIR"

# --- Commands ---------------------------------------------------------------
mkdir -p "$BINDIR"
write_launcher() {
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$2" > "$BINDIR/$1"
  chmod 755 "$BINDIR/$1"
}
write_launcher dbdesigner-fork "$APPDIR/DBDesignerFork"
[ -f "$APPDIR/DBDesignerMCP" ] && write_launcher dbdesigner-fork-mcp "$APPDIR/DBDesignerMCP"

# --- Application menu -------------------------------------------------------
mkdir -p "$APPSDIR" "$ICONDIR"
cp "$APPDIR/dbdesigner-fork.png" "$ICONDIR/dbdesigner-fork.png"
ICON=dbdesigner-fork
sed -e "s#@APPDIR@#$APPDIR#g" -e "s#@ICON@#$ICON#g" \
  "$SRC/dbdesigner-fork.desktop.in" > "$APPSDIR/dbdesigner-fork.desktop"
chmod 644 "$APPSDIR/dbdesigner-fork.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APPSDIR" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null 2>&1 && gtk-update-icon-cache -q -t "$DATADIR/icons/hicolor" 2>/dev/null || true

# --- Examples into the documents of the user --------------------------------
DOCS="$TARGET_HOME/Documents"
DIRS_FILE="${XDG_CONFIG_HOME:-$TARGET_HOME/.config}/user-dirs.dirs"
[ "$TARGET_USER" != "$(id -un)" ] && DIRS_FILE="$TARGET_HOME/.config/user-dirs.dirs"
if [ -f "$DIRS_FILE" ]; then
  d=$(sed -n 's/^XDG_DOCUMENTS_DIR="\(.*\)"$/\1/p' "$DIRS_FILE" | head -n 1)
  [ -n "$d" ] && DOCS=$(printf '%s' "$d" | sed "s#\$HOME#$TARGET_HOME#")
fi
EXAMPLES="$DOCS/DBDesigner"
as_target mkdir -p "$EXAMPLES"
copied=0
for f in "$APPDIR"/examples/*; do
  [ -f "$f" ] || continue
  if [ ! -e "$EXAMPLES/$(basename "$f")" ]; then
    as_target cp "$f" "$EXAMPLES/"
    copied=$((copied + 1))
  fi
done

# --- Uninstaller ------------------------------------------------------------
cat > "$APPDIR/uninstall.sh" <<EOF
#!/bin/sh
# Removes DBDesigner Fork $VERSION, installed $(date +%Y-%m-%d) for $([ "$MODE" = system ] && echo "all users" || echo "the user $TARGET_USER").
# The settings (~/.DBDesigner-Fork) and the examples ($EXAMPLES) are kept.
set -eu
$( [ "$MODE" = system ] && echo '[ "$(id -u)" -eq 0 ] || { echo "Needs root: sudo $0" >&2; exit 1; }' )
if [ -x "$APPDIR/DBDesignerMCP" ]; then
  # entries of this program in Claude Code / Claude Desktop, if there are any
  $( [ "$MODE" = system ] && echo "U=\${SUDO_USER:-root}; R=\"sudo -u \$U -H\"" || echo 'R=""' )
  \$R "$APPDIR/DBDesignerMCP" --unregister-claude-code >/dev/null 2>&1 || true
  \$R "$APPDIR/DBDesignerMCP" --unregister-claude-desktop >/dev/null 2>&1 || true
fi
rm -f "$BINDIR/dbdesigner-fork" "$BINDIR/dbdesigner-fork-mcp"
rm -f "$APPSDIR/dbdesigner-fork.desktop" "$ICONDIR/dbdesigner-fork.png"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database -q "$APPSDIR" 2>/dev/null || true
rm -rf "$APPDIR"
echo "DBDesigner Fork has been removed."
EOF
chmod 755 "$APPDIR/uninstall.sh"

# --- MCP server -------------------------------------------------------------
if [ -f "$APPDIR/DBDesignerMCP" ]; then
  if [ "$REG_CODE" = yes ]; then
    as_target "$APPDIR/DBDesignerMCP" --register-claude-code ||
      echo "Warning: the registration in Claude Code failed; later: dbdesigner-fork-mcp --register-claude-code" >&2
  fi
  if [ "$REG_DESKTOP" = yes ]; then
    as_target "$APPDIR/DBDesignerMCP" --register-claude-desktop ||
      echo "Warning: the registration in Claude Desktop failed; later: dbdesigner-fork-mcp --register-claude-desktop" >&2
  fi
fi

echo "Installed."
echo "  Start it from the application menu or with: dbdesigner-fork"
echo "  Examples: $EXAMPLES ($copied new)"
echo "  Remove it with: $([ "$MODE" = system ] && echo "sudo ")$APPDIR/uninstall.sh"
case ":$PATH:" in
  *":$BINDIR:"*) ;;
  *) echo "  Note: $BINDIR is not in PATH yet (it is after the next login on most systems)." ;;
esac
if [ -n "$MISSING_OPTIONAL" ]; then
  echo
  echo "Not installed (needed only for these databases):$MISSING_OPTIONAL"
  echo "  On Debian / Ubuntu: sudo apt install$(echo "$MISSING_OPTIONAL" | sed 's/([^)]*)//g')"
fi
