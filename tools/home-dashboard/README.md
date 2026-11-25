# OUI-APEX Home Dashboard

The home dashboard is a web page that runs on your computer and shows an OUI-APEX mesh live. It reads one board over USB, lists every node in the mesh, puts the nodes on a map, and keeps a searchable history of every detection. Nothing leaves your computer unless you switch on a link to a TAK server, Reticulum, or an online map layer.

It is based on the OUI-SPY Mesh dashboard in [colonelpanichacks/ouispy-detector](https://github.com/colonelpanichacks/ouispy-detector) (`home-dashboard/`), written by Colonel Panic and released under the MIT license. The web page, the history database, the map, the drone tracker and the position model come from that project. The board link, the node commands, the access control and the TAK and Reticulum links are new. The upstream license is in [LICENSE](LICENSE) and the notice is in [companion/NOTICE](../../companion/NOTICE).

## Run it

You need Python 3.9 or newer and a terminal. Run these from this folder.

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python ouispymesh.py
```

On Windows, use `py -m venv .venv`, then `.venv\Scripts\pip install -r requirements.txt` and `.venv\Scripts\python ouispymesh.py`.

Open <http://127.0.0.1:5077>. Plug in a board that runs OUI-APEX firmware. The dashboard finds it by its USB vendor ID (`0x303A`, Espressif) and asks it to identify itself. A board from another project is released after 3 seconds and skipped for a minute.

Opening the port never resets the board. The dashboard does not set the DTR and RTS lines one at a time, which would pulse the reset pin on a native USB ESP32.

| Option | What it does |
|---|---|
| *(none)* | Reads a board on USB. Listens on this computer only. |
| `--demo` | Shows a simulated five-node mesh with a day of history. Uses its own database and needs no hardware. |
| `--demo-center LAT,LON` | Sets where the demo mesh sits on the map. |
| `--demo-showcase` | Uses sample data that is safe to screenshot. |
| `--serial PORT` | Reads one port, such as `/dev/cu.usbmodem1101` or `COM5`. `--serial off` turns USB off. `--serial tcp:192.0.2.5` reads the board's USB network port (default port 4700). |
| `--mqtt HOST[:PORT]` | Subscribes to detections that nodes publish over MQTT. The password comes from `OUISPY_MQTT_PASSWORD`. |
| `--lan` | Lets other devices open the dashboard. Every device except this computer must give the access token. |
| `--new-token` | Makes a new access token, prints it once, and exits. |
| `--advertise` | With `--lan`, announces the dashboard on your network as `_ouispy._tcp` so the OUI-APEX app can find it. |
| `--prewarm-tiles` | Downloads satellite map tiles around your nodes in the background. Off by default. |
| `--download-lookups` | Downloads the public IEEE vendor list and Bluetooth SIG name lists once. Off by default. |
| `--port`, `--host`, `--db` | Set the port (default 5077), the bind address (default `127.0.0.1`) and the database file. |

On Linux, add yourself to the serial group once with `sudo usermod -aG dialout $USER` (`uucp` on Arch), then log out and back in.

## Who can open it

The dashboard can reboot nodes, so it is private by default.

- It listens on `127.0.0.1`. Only this computer reaches it.
- `--lan` is the only way to listen on other interfaces. Once you use it, every device except this computer needs the access token.
- The first `--lan` run makes the token and prints it once. Only its SHA-256 is saved, in `~/.config/ouispy/dashboard_token.sha256` with mode `0600`. If you lose the token, run `--new-token`.
- Open `http://HOST:5077/?token=TOKEN` once. The browser keeps the token in a cookie and removes it from the address.
- The dashboard refuses a request whose `Host` header is not a loopback name when it listens on this computer only, and it refuses a change that comes from another web site.
- The link is plain HTTP. Use `--lan` on a network you trust, or put an HTTPS proxy or a VPN in front of it.
- Nothing starts by itself. There is no launch agent, service or scheduled task. If you want one, write it yourself and stop it before you flash a board.
- Passwords are never stored in the database. See [MQTT](#mqtt).
- Leaflet and the Socket.IO client are included, so the page loads no third-party scripts. Map tiles are the one thing that goes online, and only when you look at an online layer.

## How it reads the board

The board sends its data over a framed link: the same Bluetooth characteristics the app uses, carried over USB serial or the USB network port (`src/usb_link.cpp`). Each frame starts with `A5 5A`, then a type, an id, a length, the payload and a CRC-16. The dashboard sends a hello, reads the device information, and subscribes to two characteristics:

| Characteristic | What the dashboard does with it |
|---|---|
| Detection events | Decodes each detection, adds it to the history, and sends Remote ID drones to the drone tracker. |
| Mesh status | Builds the node list, the signal between nodes, each node's firmware, board, uptime and filter counts. |

It pings the board every second, because the board drops the link after 4 seconds of silence. It asks every node for its status when it connects and then every 120 seconds (**Settings** → **Alerts & Map** → **Read node settings every**).

If the board you plugged in is a manager, it is the home node. If it is a plain node, the dashboard shows the mesh from that node's side.

## What you can do

- **Fleet.** Every node with its role, online or offline state, last seen time, signal to the home node, firmware, board and uptime.
- **Map.** Drag a node to place it, or use **Place on map**. Lines join nodes and show the signal in dBm. A red badge counts each node's detections in the last 15 minutes.
- **Detections and devices.** Live feed, a 24 hour chart, a device list with first and last seen, best signal and which nodes heard it, names and notes for devices and nodes, and CSV and JSON export.
- **Drones.** Remote ID drones with their flight track, pilot position and an optional FAA registry lookup (you press the button).
- **Metrics.** Detections over time, vendors, nodes and signal strength.
- **Console.** A log of what the board and the dashboard did. The board has no text console, so there is no command box.
- **Node commands.** In the node drawer or on the **Fleet Control** tab: **Read status**, **Identify** and **Reboot**, to one node or to all. A status read finishes when the node answers. **Identify** and **Reboot** finish when the board accepts the command, because the node does not confirm them. Each job says which one it was.
- **Settings.** Serial port, MQTT, map layer, notifications, and how many days to keep history (0 keeps everything, and old rows are pruned hourly).

Filters, presets, buzzer and LED, radio channel, firmware updates and the fleet key are not available here. The firmware has no remote control for them from a computer, so you set them in the OUI-APEX app. Their controls are hidden. A request for one of them is refused with that message.

## Links to other systems

The dashboard owns these links. The OUI-APEX app shows them and switches them on and off (**Settings** → **Data** → **Home dashboard**). Each one is off until you enable it.

### MQTT

MQTT carries detections from nodes that are on Wi-Fi into the dashboard. You set the broker, port, user, topic filter (default `+/detection`) and TLS in **Settings** → **MQTT**.

The dashboard does not store the password. Give it one of these:

1. Set `OUISPY_MQTT_PASSWORD` in the environment before you start the dashboard.
2. Put the password in a file only you can read and enter that file's path in **Password file**.

A request that contains a `password` field is refused.

### TAK server

The dashboard sends Cursor-on-Target events to a TAK server every 10 seconds: each node that has a map position and is online, each live Remote ID drone, and each drone's pilot. The events expire after 60 seconds.

| Setting | Meaning | Default |
|---|---|---|
| `host`, `port` | The TAK server's address. | none, 8087 |
| `proto` | `tcp`, `udp` or `tls`. | `tcp` |
| `callsign` | Prefix for node names. | `OUISPY` |
| `ca_file`, `cert_file`, `key_file` | Paths to PEM files for `tls`. The key file must not need a passphrase. | none |

You set them in **Settings** → **TAK server**. `GET /api/tak` returns `enabled`, `state` (`off`, `connecting`, `connected` or `error`), `host`, `proto`, `port`, `callsign`, `sent`, `last` and `error`.

### Reticulum

The dashboard sends alerts as LXMF messages over Reticulum. It needs two packages that are not in `requirements.txt`: `pip install rns lxmf`. If they are missing, the link reports that.

Its identity is kept in `~/.config/ouispy/reticulum_identity` with mode `0600`. The dashboard's own address is shown under **Settings** → **Reticulum** and in the app. You list the addresses that should receive alerts (32 hex digits each), and choose which alerts to send: new devices, drones, and lost nodes. Alerts of one kind are at least 10 seconds apart.

`GET /api/rns` returns `enabled`, `state`, `address`, `sent`, `failed`, `queued` and `error`.

## History

Detections and sightings are stored in `ouispy.db` next to the program, or in `ouispy-demo.db` for `--demo`. Set **Keep history for** to a number of days to prune older rows, or to 0 to keep everything. **Clear detection history** deletes every detection and keeps devices, names, groups and drones.

## Tests

```bash
python3 -m unittest discover -s tests
```

The tests need only the Python standard library. They cover the link framing, the detection and mesh status decoders, the live feed against a fake board, node commands, the access token, the TAK link against a local server and the Reticulum link against a stand-in library.

## Disclaimer

For research purposes only. Use it at your own risk and follow your local laws. The software is provided as is, with no warranty.
