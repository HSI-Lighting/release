# HSI product registry

The one place that says how every HSI product identifies itself, for OTA (HSI Device Configurator
"Use latest build", DALI Admin gateway OTA) and for the HSI Firmware Flasher library. Both read the one
published library: `firmware-flasher/latest.json` -> `firmware`.

**Publishing refuses a library that does not match this file.** `publish.ps1 firmware-flasher firmware`
and `./publish.sh firmware-flasher firmware` run `tools/check_products.py` first. A firmware can be added to
the library only after its row is here. Adding a product, a board, a new product id or a hand-made entry
means editing this file in the same change.

## Rules

- **Builds name** = the product word in the library entry's notes, `[HSI BUILDS] <builds name> <board>, built <YYYY-MM-DD HH:MM[:SS]> from <commit>. ...`.
  That word is also the HSI BUILDS folder (`HSI BUILDS/firmware/<builds name>/V<ver>/<board>/`) and the name the apps ask the
  library for. The apps find only entries in this form. A hand-written entry with other notes is invisible to OTA.
- **Product id** = the 16-bit id in the image's 32-byte `HSI-OTA1` trailer (vendor `0x2269`). The device reports it as
  `productId` in `/api/status` `identity`, and refuses an image stamped for another product. A new product takes the next free id in
  its family: Wall Display `0x01xx`, Wireless Knob `0x02xx`, gateways `0x03xx`, WallkeyCore `0x04xx`. Never reuse an id. Never give two
  products one id: the Modbus Gateway Eth+WiFi 2.2.0-2.2.1 used the X0103's `0x0303` and the apps took it for a DALI master.
- **hardwareRev** = what the device reports as `identity.hardwareRev` (`/api/status`; over BLE, the setup document). The apps pick the
  device's screen and its builds name from it. Changing it in firmware needs the apps changed first.
- **Legacy code** = an older id still accepted while units in the field move to the new one.
- `-` = none. A builds name with product id `-` is published without a product check.

## Products

| Builds name | Boards | Product id | Legacy | hardwareRev | Product | Firmware repo |
|---|---|---|---|---|---|---|
| SQK6B | base, mid, top | 0x0101 | - | WD6B-SD (variant SQK6B) | Wall Display Sq.Kn.6B | HSI_WALL_DISPLAY_CORE |
| SQKFP | base, mid, top | 0x0102 | - | WD6B-SD (variant SQKFP) | Wall Display Sq.Kn.FP | HSI_WALL_DISPLAY_CORE |
| TD8B | base, mid, top | 0x0103 | - | WD6B-SD (variant TD8B) | Wall Display TD.8B | HSI_WALL_DISPLAY_CORE |
| RNDK5B | base, mid, top | 0x0104 | - | WD6B-SD (variant RNDK5B) | Wall Display Rd.Kn.5B | HSI_WALL_DISPLAY_CORE |
| AMLKN5B | base, mid, top | 0x0105 | - | WD6B-SD (variant AMLKN5B) | AML.Kn.5B (AMOLED knob) | HSI_WALL_DISPLAY_CORE |
| WirelessKnob | k518 | 0x0201 | 1 | JC3636K518 | Wireless Knob WKn518 | ESP32s3-wireless-knob |
| WirelessKnob | k718 | 0x0202 | 6 | JC3636K718 | Wireless Knob WKn718 | ESP32s3-wireless-knob |
| S3X3 | net, dali, ui | 0x0301 | - | S3X3-W5500 | S3x3 3-Line DALI Master | S3x3 |
| HSI-GEARS | net, sim_a, sim_b, ui | 0x0302 | - | - | HSI-GEARS DALI gear simulator | HSI-GEARS |
| X0103 | net, dali, ui | 0x0303 | - | X0103 | X0103 REBUILD2 3-Line DALI Master | X0103 REBUILD2 |
| 90111 | net, ui | 0x0304 | - | 90111 | 90111 REBUILD2 3-Line DALI Master (its DALI micros take no OTA) | 90111 REBUILD2 |
| KNX | net, bus, ui | 0x0305 | - | KNX-V2 | KNX Gateway | KNX gateway |
| E740K | main | 0x0306 | - | 90122-MINI | Modbus WiFi E740K V1 (90122 mini-n4 node) | Modbus_MQTT_Gateway-90122, branch E740K_MB_V1 |
| MBWIFI | main | 0x0307 | - | 90122-wifi | Modbus WiFi V1 (90122 WROOM-32E/32UE gateway) | Modbus_MQTT_Gateway-90122, branch WIFI_MB_V1 |
| MBW5500 | main | 0x0308 | - | Modbus Gateway | Modbus Gateway Eth+WiFi (MB-ADM-W5500) | Modbus_MQTT_Gateway-90122, branch MB-ADM-W5500 |
| WallkeyCore | main | 0x0401 | 4 | WALLKEY (variant = panel model) | WallkeyCore keypads M9.8B, X9.6B, M15.D2.4B, M15.D1.4B | HSI-WallkeyCore |
| X20 | main | - | - | X20-ESP12 | X20 8-button panel (ESP8266) | X20 |
| BLEGW | dali | - | - | (BLE: version string ble_GATEWAY_v...) | BLE DALI 3-line Gateway (DALI Admin BLE gateway OTA) | DALI-BLE-Master |

## Hand-made entries

Library entries without `[HSI BUILDS]` notes: full-flash images for the Flasher only, never offered over OTA. Each must be listed
here by its exact entry name. Prefer a `[HSI BUILDS]` entry for anything new.

| Entry name | Product |
|---|---|
| 90112 Relay | HSI Relay 90112 |
| 90122 Modbus Eth+WiFi | Modbus Eth+WiFi gateway, original firmware (before MB-ADM-W5500) |
| U5-DMX Master DMX | DMX Master 90108 U5 |
| U10-DMX Master COM | DMX Master 90108 U10 |
| 90111-Morteza COM 2026-08-03 | 90111 original firmware, COM |
| 90111-Morteza LCD 2026-08-03 | 90111 original firmware, LCD |
| 90111-Morteza DALI 2026-08-03 | 90111 original firmware, DALI micro |
| 90111 DALI V2.3.2 | 90111 DALI micro |
| alireza_X0103 build_01 12-Aug-2026 COM | X0103 original firmware, COM |
| alireza_X0103 build_01 12-Aug-2026 LCD | X0103 original firmware, LCD |
| alireza_X0103 build_01 12-Aug-2026 DALI | X0103 original firmware, DALI |
| BLE DALI Gateway (USB-C flash) g191ef28 | BLE DALI Gateway, Aug 12 known-good image |
| BLE DALI Gateway (USB-C flash) 2026-10-26 0c144ad | BLE DALI Gateway |
| DALI Slave 90113 | DALI Slave 90113 |
| WallkeyCore V4.8 26-OCT2026DEBUG | WallkeyCore debug build |
