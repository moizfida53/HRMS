# TMM POS Print Agent

Lets the POS (hosted on your VPS) print silently to the restaurant's network printers.

## Why it exists
A web page cannot open a connection to `192.168.x.x:9100`, and your server cannot see the restaurant's LAN. The browser draws the ticket and posts it to this agent on `http://127.0.0.1:9101`; the agent sends it to the printer. No print dialog, no pop-ups.

## Install (once per restaurant, on the PC that runs the POS browser)
1. Install Node.js LTS from nodejs.org.
2. Copy this folder to the PC, e.g. `C:\TMM-PrintAgent`.
3. Edit `agent.config.json`: put your POS address in `allowedOrigins`, exactly as in the browser bar, e.g. `"https://pos.example.com"`.
4. Double-click `start-agent.bat`. Leave the window open (minimised).
5. Start it automatically: press Win+R, type `shell:startup`, and put a shortcut to `start-agent.bat` there.
6. In the POS: Printer Settings. The strip at the top should say **Print Agent connected**.

(Option: `npx pkg pos-print-agent.js --targets node18-win-x64` makes a single `.exe` with no Node needed.)

## Printers
- Network (LAN/Ethernet) ESC/POS thermal printers, 80 mm or 58 mm, raw port **9100** (Epson, Xprinter, Star in ESC/POS mode, Bixolon, Rongta, most Chinese 80 mm printers).
- Give each printer a fixed IP (static or a DHCP reservation in the router).
- A printer on a USB cable is not reachable this way.

## Notes
- Chrome / Edge allow a secure (https) site to call `http://127.0.0.1`. Firefox and Safari may block it; use Chrome or Edge on the POS PC.
- The first time, Chrome may ask the site for "local network access" permission: choose Allow.
- The agent only accepts printers on private addresses (10.x, 172.16-31.x, 192.168.x.x).
