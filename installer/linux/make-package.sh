#!/bin/sh
# Makes the Linux package installer/Output/dbdesigner-fork-<version>-linux-<arch>.tar.gz
# from the programs in bin/ - the counterpart of DBDesignerFork.iss.
#
# Build the program, the plugins and the MCP server first (see README), then
# run it from the project directory:
#
#   sh installer/linux/make-package.sh
#
# The package holds the programs (debug information stripped, the symbols
# kept), Data, Gfx, Doc, the licence, the examples and install.sh. The client
# libraries of SQLite, MySQL and Firebird are not in it: they come from the
# distribution (install.sh names the packages that are missing).
set -eu

cd "$(dirname "$0")/../.."
BIN=bin

[ -x "$BIN/DBDesignerFork" ] || { echo "No $BIN/DBDesignerFork - build the program first (lazbuild DBDesignerFork.lpi)." >&2; exit 1; }

# The version as in the project options (DBDesignerFork.lpi, Version Info)
lpi_value() { sed -n "s/.*<$1 Value=\"\([0-9]*\)\".*/\1/p" DBDesignerFork.lpi | head -n 1; }
MAJOR=$(lpi_value MajorVersionNr); MINOR=$(lpi_value MinorVersionNr); REV=$(lpi_value RevisionNr)
VERSION="${MAJOR:-0}.${MINOR:-0}.${REV:-0}"
ARCH=$(uname -m)

NAME="dbdesigner-fork-$VERSION-linux-$ARCH"
OUT=installer/Output
STAGE="$OUT/$NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE/app" "$STAGE/app/examples"

echo "DBDesigner Fork $VERSION ($ARCH)"

# The programs
cp "$BIN/DBDesignerFork" "$STAGE/app/"
found_plugin=no
for f in "$BIN"/DBDplugin_*; do
  case "$f" in *.exe|*.dll) continue ;; esac
  [ -x "$f" ] || continue
  cp "$f" "$STAGE/app/"
  found_plugin=yes
done
[ "$found_plugin" = yes ] || echo "Warning: no plugins in $BIN (lazbuild Plugins/*/*.lpi), they are left out" >&2
if [ -x "$BIN/DBDesignerMCP" ]; then
  cp "$BIN/DBDesignerMCP" "$STAGE/app/"
else
  echo "Warning: no $BIN/DBDesignerMCP (lazbuild mcp/DBDesignerMCP.lpi), the MCP server is left out" >&2
fi
if command -v strip >/dev/null 2>&1; then
  for f in "$STAGE"/app/DBDesignerFork "$STAGE"/app/DBDplugin_* "$STAGE"/app/DBDesignerMCP; do
    [ -f "$f" ] && strip --strip-debug "$f"
  done
fi

# Data, pictures, help, licence
cp -R "$BIN/Data" "$BIN/Gfx" "$BIN/Doc" "$STAGE/app/"
cp "$BIN/Copying.txt" "$STAGE/app/"
mkdir -p "$STAGE/app/licenses"
cp installer/licenses/SQLite-LICENSE.txt "$STAGE/app/licenses/" 2>/dev/null || true

# The examples: install.sh copies them into the documents of the user
for f in order.xml beispiel_sqlite.sql beispiel_sqlite.xml beispiel_firebird.sql beispiel_firebird.xml; do
  cp "$BIN/Examples/$f" "$STAGE/app/examples/"
done
for f in beispiel.sqlite beispiel.fdb; do
  if [ -f "$BIN/Examples/$f" ]; then
    cp "$BIN/Examples/$f" "$STAGE/app/examples/"
  else
    echo "Warning: no $BIN/Examples/$f (python3 tools/make-example-databases.py), it is left out" >&2
  fi
done

# The icon for the menu (made once from Gfx/Icon48.xpm)
cp installer/linux/dbdesigner-fork.png "$STAGE/app/dbdesigner-fork.png"

cp installer/linux/install.sh "$STAGE/install.sh"
cp installer/linux/dbdesigner-fork.desktop "$STAGE/app/dbdesigner-fork.desktop.in"
chmod 755 "$STAGE/install.sh"
echo "$VERSION" > "$STAGE/app/VERSION"

tar -C "$OUT" -czf "$OUT/$NAME.tar.gz" "$NAME"
rm -rf "$STAGE"
echo "Written: $OUT/$NAME.tar.gz ($(du -h "$OUT/$NAME.tar.gz" | cut -f1))"
