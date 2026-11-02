VanaClient: a new FINAL FANTASY XI client (early test)

What it is
- A native client for FINAL FANTASY XI, for Linux and Windows. No PlayOnline, no Wine needed on Linux.
- It plays on the same server, account and characters as the original client: pick "Play Vana Client" in the
  launcher, or "Play Original" for the client you know. Your characters are the same in both.
- It uses your own FINAL FANTASY XI install and never changes it. Your macros and settings go to its own folder
  (seeded from the game's on first start).
- It is open source: a fork of vana-client by Lenon Kitchens (MIT licence), https://github.com/Blizz127/vana-client.

Please note
- Do not play the same account in both clients at the same time: the server signs the first one out.
- This is an early test. It can crash or show things wrong. Keep "Play Original" for anything important.
- Gamepads work (Xbox / PlayStation style). Config > Settings > Gamepad turns it off or changes the sticks.
- /rot is a one-button helper that does the next sensible action in a fight (one action per press). Its autocast is
  off here; /autocast on turns it on for the session if you want it.

Known gaps
- The Windows build has not had much testing on real Windows PCs yet; Linux has had more.
- Some event mini-games and rare event script steps are not done yet.
- Controller use with the on-screen keyboard is new; tell us where it gets in the way.
- The search (/sea) may time out on some servers until their side is updated.
- No macOS build.

Reporting a bug
- Say what you did, where (zone), roughly when (your time zone), and what you expected instead.
- A screenshot helps.
- Attach the log: vana-client.log in the game's folder that the launcher opens for this client (the newest one is
  vana-client.log, the one before it vana-client.prev.log). It holds no password.
- Send it to the Banshee Realm team the way you usually reach them.

FINAL FANTASY is a registered trademark of Square Enix Holdings Co., Ltd. This is an unofficial fan project.
