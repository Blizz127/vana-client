# Running on a Steam Deck (Game Mode)

The Linux release (`vana-client-linux-x86_64`) is built in the Steam Runtime 3 "sniper" SDK (`release/sniper.Dockerfile`,
`release/build-linux-sandbox.sh`), the runtime Steam itself uses for native Linux games, so it runs on SteamOS as is.
This page adds the client as a non-Steam game so it starts from Game Mode with the pad working.

## 1. Put the client and the game files in place (Desktop Mode)

1. Download `vana-client-linux-x86_64` from the releases page, or build it with `release/build-linux-sandbox.sh`.
   Put it somewhere permanent, for example `/home/deck/Applications/vana-client/`, and make it executable
   (`chmod +x vana-client-linux-x86_64`).
2. Install or copy the game data as described in the README ("Install the game data"). The default place is
   `~/.local/share/vana-client/game/FINAL FANTASY XI`; on an SD card, point `game_dir` at it in the config (below).

## 2. A config of its own for the Deck

`FFXI_CONFIG` names the config file the client reads and writes, so the Deck's settings stay apart from a desktop
install's (the client's log and per-character chat history are kept beside it). A file with only the values you want to
change is enough; everything missing takes its default:

```json
{
  "tool": { "0034": 3 }
}
```

Save it as `/home/deck/.config/vana-client/deck.json`.

- `"tool": { "0034": 3 }` is the window mode: borderless at the desktop's size. The client's own default is a
  1280x800 window (0034 = 1), which is the Deck's screen size but leaves the window frame to gamescope; 2 is borderless at the window size,
  0 is full screen. Settings > Window Mode in the client changes it too, and is saved to this file.
- `"game_dir": "/run/media/mmcblk0p1/ffxi"` (the folder that holds `FINAL FANTASY XI`) if the game files are not in the
  default place. Use your own path.
- The gamepad settings (`gamepad`, `gamepad_deadzone`, `gamepad_camera_speed`) are in the same file; the Deck's sticks
  are fine at the defaults.

## 3. Add it as a non-Steam game

In Desktop Mode, in Steam: Games > Add a Non-Steam Game to My Library > Browse, pick `vana-client-linux-x86_64`, add it.
Then open its Properties:

- Name: whatever you like.
- Launch Options:

  ```
  FFXI_CONFIG=/home/deck/.config/vana-client/deck.json VANA_MANAGED=1 %command%
  ```

  `FFXI_CONFIG` is the file from step 2. `VANA_MANAGED=1` says something else owns the game files and the client's
  updates (you, by hand, or a launcher): the client then makes no patch-server or release lookups and shows no Update
  buttons, and keeps each character's macros, equipment sets and map markers in its own data folder (not the game's, which
  may be on a card that cannot be written). Leave it out to keep the in-app updates and the game folder's USER files.
- Compatibility: leave Proton unticked. This is a native Linux program.

Steam sets `SteamAppId` / `SteamGameId` for it; the client reads that as "started by Steam" (see Controller below).

## 4. Controller

The client reads the pad itself (Linux evdev, through the controller Steam presents), so in Properties > Controller,
choose a layout that passes the pad through as a plain gamepad: the "Gamepad" template (Xbox-style), not one that turns
the sticks or trackpads into a mouse or keyboard. The client's mapping is the README's "Gamepad" table:

- Left stick walks (a cursor in windows), right stick turns the camera (and zooms the map window), the D-pad moves the
  cursor or cycles targets, A confirms, B cancels, X is the main menu (Backspace in a text field), Y locks on, the
  bumpers are the log and window views, LT / RT held are the Ctrl / Alt macro palettes, Select opens the chat line,
  Start is the log-out prompt, R3 is `/map`.
- The back grips (L4 / R4 / L5 / R5) and the trackpads are not read by the client. Bind them in the Steam layout to keys
  if you want them (for example a grip to the Numpad keys the layout uses).
- Text entry: when a text field opens (the chat line, the login screen, the character name) and the pad was the last
  thing used, the client asks Steam to raise its on-screen keyboard, which Steam draws over the game and types into it.
  The client's own keyboard (see the README) is used where Steam is not providing one. You can always bring up Steam's by
  hand with the Steam button + X.

## 5. First start

Start it from the Game Mode library. With no game files yet it offers to download them, or to use an install already on
disk. Log in with the on-screen keyboard (A types, B backspaces, Start sends Enter). Check the window mode took (borderless,
filling the screen); if it did not, Settings > Window Mode.

Nothing here is specific to a server: the server and account are entered at the login screen as on any desktop.
