# Omarchy Multiroom Speakers

[![CI](https://github.com/mahype/omarchy-multiroom-speakers/actions/workflows/ci.yml/badge.svg)](https://github.com/mahype/omarchy-multiroom-speakers/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Omarchy 4](https://img.shields.io/badge/Omarchy-4-black.svg)](https://omarchy.org)
[![Local only](https://img.shields.io/badge/network-local%20only-lightgrey.svg)](#what-it-stores-and-where-it-connects)

Play this computer's sound on AirPlay speakers — HomePods, Sonos, Apple TV,
AirPlay receivers — in one room or in several at once, from the Omarchy bar.

> Work in progress.

## Modes

| | Direct | Multiroom |
|---|---|---|
| How | PipeWire's own AirPlay (RAOP) sinks | a pipe sink feeds a private [OwnTone](https://github.com/owntone/owntone-server) instance |
| One room | that speaker becomes the default output | — |
| Several rooms | a combine sink with latency compensation | AirPlay 2 on one shared clock, like a Mac or iPhone |
| Sync between rooms | host-timed; rooms can drift apart slightly | in sync |
| Speakers | AirPlay | AirPlay 2, AirPlay, Chromecast |
| Delay | about 1–2 s | about 2 s |
| Needs | `pipewire-zeroconf` | OwnTone (see below) |

Switch between **Off**, **Direct** and **Multiroom** at the top of the panel.
Each mode lists the speakers it can reach; the switch next to a speaker adds
it to the rooms that play. Rooms are remembered per mode. **Off** removes
everything the plugin created and returns to the output used before.

Every speaker shows its volume slider right in its row; rooms start at their
remembered volume, 25 % the first time. The mouse wheel scrolls the panel and
never turns a slider. In multiroom mode a click on a speaker unfolds:

- **Connection** — AirPlay or Chromecast, for devices that offer both (they
  are listed once). A playing device switches over at once.
- **Delay** (−1000 … 1000 ms) to line up rooms by ear.
- **PIN** for an Apple TV that asks for pairing.

**Volume keys** move all playing rooms together and keep their balance. The
signal itself stays at full level: the plugin's outputs (the pipe to OwnTone,
the combined AirPlay output) are held at 100 %, so the speakers never get a
weakened signal.

The bar icon shows the number of playing rooms. It turns red only when
something is wrong: PipeWire or OwnTone fail, a chosen room refuses or loses
its connection, or a command fails. A room that is merely away (standby) is
not an error.

Both modes suit music and video (players delay the picture to match); neither
suits games or calls.

## Sonos

Sonos speakers with AirPlay 2 (One, Era, Five, Move, Roam, Beam, Arc, Port,
Amp, Play:5 gen 2, …) appear in both modes like any other AirPlay speaker and
play in sync with HomePods in multiroom mode. Direct mode needs UDP ports
6001–6002 open (see [Firewall](#firewall)).

Older Sonos speakers without AirPlay (Play:1, Play:3, Play:5 gen 1, Playbar,
Connect) are not supported; [Sonomarchy](https://github.com/nixfred/sonomarchy)
streams to those over UPnP.

## Requirements

- Omarchy with the Quickshell-based `omarchy-shell`
- **Direct:** `sudo pacman -S pipewire-zeroconf`
- **Multiroom:** OwnTone. HomePods with **HomePod OS 27** refuse OwnTone 29.3
  (the current release and AUR package) with `403 Forbidden`. The fix is
  merged upstream but not released yet, so build a current OwnTone for your
  user:

  ```bash
  yay -S owntone-server              # dependencies (and a fallback binary)
  tools/build-owntone.sh             # builds a pinned upstream commit
  ```

  The script installs to `~/.local/share/omarchy-multiroom-speakers/owntone`,
  where the plugin looks first; no sudo, nothing system-wide. The packaged
  system service `owntone.service` is not used and can stay disabled. The
  panel warns when the OwnTone in use is too old for HomePod OS 27.

### Firewall

With ufw active, the speakers must be able to answer:

```bash
sudo ufw allow 5353/udp        # mDNS discovery
sudo ufw allow 6001:6004/udp   # 6001–6002 direct (RAOP), 6003–6004 OwnTone AirPlay 2
```

## Installation

```bash
omarchy plugin add https://github.com/mahype/omarchy-multiroom-speakers.git --enable
```

## Remove

Switch the mode to **Off** first, then:

```bash
omarchy plugin remove io.github.mahype.omarchy-multiroom-speakers
rm -rf ~/.config/omarchy-multiroom-speakers            # mode and rooms
rm -rf ~/.local/state/omarchy-multiroom-speakers       # OwnTone database, log, pipe
rm -rf ~/.local/share/omarchy-multiroom-speakers       # OwnTone built by the script
rm -rf ~/.cache/omarchy-multiroom-speakers             # OwnTone sources
```

## What it stores and where it connects

| What | Where |
|---|---|
| Mode, rooms per mode, previous output | `~/.config/omarchy-multiroom-speakers/config.json` |
| OwnTone config, database, log, pipe | `~/.local/state/omarchy-multiroom-speakers/` |
| OwnTone API | `http://127.0.0.1:3689`, from this machine only (`trusted_networks = localhost`) |
| Speakers | your local network: AirPlay (RTSP/UDP), Chromecast |

What the plugin creates, all with fixed names so it finds them again after a
restart and touches nothing else:

- PipeWire modules loaded through `pactl`: `module-raop-discover` (direct),
  `module-combine-sink` named `omarchy_multiroom_direct` (direct, several
  rooms), `module-pipe-sink` named `omarchy_multiroom` (multiroom). They live
  until PipeWire restarts; the plugin loads them again when needed.
- A transient systemd user unit `omarchy-multiroom-speakers-owntone` running
  OwnTone with local audio and MPD disabled. It keeps playing when the shell
  restarts.

External programs: `pactl`, `curl`, `systemctl`/`systemd-run` (user
instance), `grep`, `test` and `install`, always called with argument arrays,
never through a shell. No sudo or pkexec at runtime.

OwnTone announces its (empty) library on the network like any DAAP server.

## Troubleshooting

Two logs record what happens, both in `~/.local/state/omarchy-multiroom-speakers/`:

- `plugin.log` — mode switches, every command that changes something with its
  result, speakers found, lost, selected or dropped, retries.
- `owntone.log` — OwnTone at level `info`: sessions set up per speaker,
  refusals, dropouts.

`tools/collect-logs.sh [minutes]` prints both together with PipeWire's AirPlay
messages and the current sinks, modules and speakers.

Behaviour worth knowing:

- **Volume.** A room starts at its remembered volume, 25 % the first time.
  PipeWire's AirPlay sinks start at 100 %, the speaker's full volume, so the
  plugin sets the room's volume before any sound reaches it.
- **AirPlay 1 vs. 2.** OwnTone lists a speaker as AirPlay 1 first and
  switches to AirPlay 2 a few seconds later. HomePods refuse AirPlay 1, so
  the plugin waits for AirPlay 2 before selecting remembered rooms, and keeps
  sound away from OwnTone until then.
- **One device, one session.** A speaker offering AirPlay and Chromecast is
  selected with one of them only.
- **Dropouts.** A chosen room that drops out is marked in the panel and asked
  again up to three times, 20 seconds apart. Rooms that are not on the network
  (standby, off) stay in the list as "not found" and join when they return.
- **Sync.** OwnTone times HomePods over NTP unless it may bind the PTP ports
  319/320: `sudo setcap cap_net_bind_service=+ep ~/.local/share/omarchy-multiroom-speakers/owntone/sbin/owntone`
  (again after every rebuild).
- **Chromecast is not in sync.** OwnTone buffers Chromecast on its own; it
  plays about two seconds behind the AirPlay rooms. For multiroom use a
  device's AirPlay connection; the panel says so under the Chromecast choice.
  Speakers that cannot start OwnTone's receiver app (seen with Samsung
  soundbars) are refused.
- **Switching back from Chromecast.** A device that casts (seen with KEF)
  stops announcing AirPlay, and OwnTone does not list it again when it does.
  The plugin remembers each device's connections, so AirPlay stays
  selectable; when the chosen connection is still missing after 12 seconds
  while the device is around, it restarts OwnTone (at most every five
  minutes) and the rooms come back after a few seconds of silence.

## Keyboard and scripting

```bash
omarchy-shell io.github.mahype.omarchy-multiroom-speakers toggle
omarchy-shell io.github.mahype.omarchy-multiroom-speakers mode multiroom   # off | direct | multiroom
omarchy-shell io.github.mahype.omarchy-multiroom-speakers room Badezimmer on   # on | off | toggle
omarchy-shell io.github.mahype.omarchy-multiroom-speakers expand KEF
omarchy-shell io.github.mahype.omarchy-multiroom-speakers status
```

## Development

```bash
node --test tests/          # unit tests
bash tests/check-manifest.sh
```

Link the checkout into `~/.config/omarchy/plugins/` and run
`omarchy restart shell` after changing code.

## License

MIT
