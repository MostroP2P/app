#!/bin/sh
# Adds Mostro to the desktop's application menu, with its icon, for the
# current user. Run it from the unpacked folder, and again after moving that
# folder; `./install.sh --uninstall` removes the entry, the icon and the link.
#
# The entry and the icon are named after the application ID: on Wayland the
# compositor finds the entry by the window's app ID and ignores the icon the
# window sets itself, so without them the app shows a generic icon.
set -eu

APP_ID=foundation.mostro.app
BUNDLE=$(cd "$(dirname "$0")" && pwd -P)
DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
ENTRY=$DATA_HOME/applications/$APP_ID.desktop
ICON=$DATA_HOME/icons/hicolor/256x256/apps/$APP_ID.png
# The entry starts the app through this link to the folder: GLib looks for
# the program before expanding `%%`, so a folder named `100%` never launched.
LINK=$DATA_HOME/$APP_ID.bundle

refresh_menu() {
  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q "$DATA_HOME/applications" || true
  fi
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$ENTRY" "$ICON" "$LINK"
  refresh_menu
  echo "Removed Mostro from the application menu."
  exit 0
fi

if [ ! -x "$BUNDLE/mostro" ]; then
  echo "install.sh: no mostro binary next to this script ($BUNDLE)" >&2
  exit 1
fi

case $LINK in
  *%*)
    echo "install.sh: the menu cannot launch from a path with % ($LINK)" >&2
    exit 1
    ;;
esac

# The Exec value is quoted, so `"`, `` ` ``, `$` and `\` take a backslash,
# which the string escape rule then doubles.
exec_path=$(printf '%s' "$LINK/mostro" |
  sed -e 's/[\\]/\\\\\\\\/g' -e 's/["`$]/\\\\&/g')

mkdir -p "$(dirname "$ENTRY")" "$(dirname "$ICON")"
ln -sfn "$BUNDLE" "$LINK"
cp "$BUNDLE/data/$APP_ID.png" "$ICON"
while IFS= read -r line; do
  case $line in
    Exec=*) printf 'Exec="%s"\n' "$exec_path" ;;
    *) printf '%s\n' "$line" ;;
  esac
done <"$BUNDLE/data/$APP_ID.desktop" >"$ENTRY"
refresh_menu
echo "Added Mostro to the application menu ($ENTRY)."
