<img width="1920" height="1080" alt="pls_mechanic_thumbnail_1920" src="https://github.com/user-attachments/assets/cc57098f-97fa-4b6d-8bf7-b8d5e4a2d3cb" />

# :wrench: pls_mechanic – Realistic Mechanic Job

> ### Every kilometre counts.
> Realistic vehicle wear, true-to-life OBD diagnostics and fully animated workshop work – **free & open source**.

![ESX](https://img.shields.io/badge/ESX-supported-2ea043?style=for-the-badge) ![QBCore](https://img.shields.io/badge/QBCore-supported-2ea043?style=for-the-badge) ![ox_lib](https://img.shields.io/badge/ox__lib-required-3b82f6?style=for-the-badge)
![Inventory](https://img.shields.io/badge/inventory-ox%20%C2%B7%20qb%20%C2%B7%20qs%20%C2%B7%20codem%20%C2%B7%20core-6b7280?style=for-the-badge) ![Target](https://img.shields.io/badge/target-ox%20%C2%B7%20qb%20%C2%B7%20markers-6b7280?style=for-the-badge)
![Free](https://img.shields.io/badge/free-open%20source-f59e0b?style=for-the-badge) ![Languages](https://img.shields.io/badge/lang-EN%20%C2%B7%20CS-6b7280?style=for-the-badge) ![Version](https://img.shields.io/badge/version-1.0.0-6b7280?style=for-the-badge)

[![Join our Discord](https://img.shields.io/badge/Discord-Join%20the%20community-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.com/invite/HyNKsABYrb)

> :speech_balloon: **[Join our Discord](https://discord.com/invite/HyNKsABYrb)** – support, updates, suggestions and the first look at new Polisek scripts.

---

Most mechanic scripts are a progress bar and a repaired car. **pls_mechanic turns the mechanic job into actual work.**

Every car on your server ages with its kilometres. Oil runs out, brake pads wear down, a timing belt snaps, a neglected engine starts to misfire – and **the driver feels it on the road**. The mechanic finds the problem with an OBD scanner and fixes it part by part. He opens the hood, slides under the car, drains the oil into a pan and carries the old part out.

:arrow_forward: **[Watch: Trailer]([https://www.youtube.com/watch?v=VIDEO_1_TRAILER](https://youtu.be/tO_KwmeAkJ4))**

---

## :sparkles: At a glance

| | |
|---|---|
| :red_car: **Realistic vehicle model** | Mileage, 11 service parts, 13 core parts, collisions by impact zone, engine temperature, EV support |
| :mag: **OBD diagnostics** | Scanner under the dashboard, React report with part states, next service and real fault codes |
| :hammer_and_wrench: **Animated repairs** | 40+ step-by-step scenes – hood, wheels, lying under the car, drain pan, test run |
| :package: **Parts logistics** | A missing part pauses the job, a route leads to the storage, you carry the box back |
| :arrow_up: **Lifts & jacks** | Smooth synced car lifts, a jack that tilts one corner of the car |
| :racing_car: **Tuning** | Performance stages + full Benny's-style catalogue, live preview, animated installation |
| :shopping_cart: **Customer catalog** | Customers pick their own tuning with live preview and prices, the mechanic gets the order |
| :moneybag: **Economy** | Supplier with supply runs, itemized bills, commission, crafting from salvage |
| :articulated_lorry: **Field work** | Push, flip, slim jim, impound, flatbed winch, jump start, 5 NPC mission types |
| :building_construction: **In-game creator** | Unlimited workshops, 11 point types, permission matrix per job grade |
| :shield: **Secure** | Server-authoritative, secure events, rate limits, mileage and plate-spoof protection |

|   |   |   |
|:-:|:-:|:-:|
| <img width="1415" height="877" alt="image" src="https://github.com/user-attachments/assets/f786f86a-894f-474f-b296-44ea7095e058" />
 |  |<img width="1466" height="1072" alt="image" src="https://github.com/user-attachments/assets/11ad7ba4-335f-4078-9a64-d5bcefa95426" />
 |

---

## :red_car: Realistic vehicle model

- :straight_ruler: **Mileage for every vehicle** – saved for owned cars, optional odometer above the minimap.
- :oil_drum: **11 service parts with km intervals** – oil, air / fuel filter, spark plugs, coolant, brake fluid, transmission fluid, brake pads, tyres, timing belt, EV battery coolant.
- :gear: **13 core parts** – engine, transmission, clutch, radiator, alternator, battery, fuel pump, brakes, suspension, alignment, turbo, EV battery, EV motor.
- :warning: **Neglect has consequences** – an overdue service starts damaging the linked core parts, a worn-out timing belt snaps.
- :boom: **Collisions by impact zone** – a frontal crash hits the radiator and engine, a side hit the suspension and alignment.
- :thermometer: **Engine temperature** – warning, power cut, then the engine shuts down until it cools.
- :zap: **Electric vehicles** – own parts, no oil or timing belt, extra drain from a worn battery.
- :detective: **NPC & stolen cars** come with a random history (20 000–250 000 km). Cars bought in a vehicle shop start brand new.

### :oncoming_automobile: The driver feels it

| Part | Symptoms |
|---|---|
| Engine | power loss · misfires · stalling · smoke · won't start |
| Transmission / clutch | slow shifts · limp mode · clutch slip under throttle |
| Battery / alternator | slow cranking · flickering lights · dead battery |
| Brakes / pads / fluid | longer braking distance |
| Suspension / alignment | wobble · pulling to one side · lower top speed |
| Tyres | less grip · blowouts at high speed |
| Radiator / coolant | overheating · steam from the engine bay |

> :eyes: Smoke and steam are networked – everyone around sees a dying car.



---

## :mag: OBD diagnostics

1. Plug the **OBD scanner** in under the dashboard and read the car on a tablet.
2. The **diagnostics report** shows every part with its state, the next service in km, damaged body parts, real fault codes (`P0300`, `P0520`, `P0217`…) and installed tuning.
3. Tick the jobs, press **Start repair** – the whole job runs as one workflow.

:repeat: The last report can be reopened for 10 minutes without a new scan.



---

## :hammer_and_wrench: Animated repair workflow

- :clipboard: **Checked before it starts** – permission, location (bay, lift, jack) and tools. No clicking through ten steps to fail on the last one.
- :film_frames: **Every repair is its own scene** – oil change with a drain pan, gearbox swap lying under the car, brakes at each wheel, battery swap with sparks, engine test run afterwards. 40+ scenes built from editable presets.
- :wrench: **Body damage part by part** – doors, hood, trunk, windows, bumpers, headlights, tyres, wheels and bodywork. Everything else stays damaged.
- :package: **Parts logistics** – heavy parts don't have to be in your pockets. A missing part pauses the job, **Take parts for the job** at the storage gives you exactly what's missing, you carry the box back and continue.
- :arrow_up: **Car lifts** rise smoothly and are synced for everyone. **Car jacks** lift one corner. Some jobs need a lift, a bay or a jack.
- :x: Cancel anytime with <kbd>X</kbd> or the target on the car.

:arrow_forward: **[Watch: Repair workflow](https://www.youtube.com/watch?v=VIDEO_2_REPAIR_WORKFLOW)**

---

## :racing_car: Tuning

| :fire: Performance | :art: Visual (Benny's style) |
|---|---|
| Engine, brakes, transmission, suspension, armor, turbo | Paint (160 colours + RGB), every body mod, all wheel types |
| Installed with stage items, dependencies checked | Interior, xenon, neon, tyre smoke, window tint, plate style, horns |
| A removed part goes back to the mechanic | Prices with a per-workshop markup |

- :movie_camera: **Live preview** with an orbit camera and a cart – drafts survive closing the menu.
- :toolbox: **Step-by-step installation** – the mechanic carries the parts crate, fits each part where it belongs, calibrates on a laptop and tests the result.

### :shopping_cart: Customer catalog – the customer picks, the mechanic builds

No more *"a bit more to the left… no, the other spoiler"*. The customer drives into the tuning bay and opens the **Tuning catalog** on their own car.

1. :eyes: **The customer browses** – same menu, live preview on the car, prices with the workshop markup.
2. :incoming_envelope: **Send order** – the preview is reverted and mechanics on duty get a notification with the plate, item count and total.
3. :wrench: **The mechanic opens tuning** – the cart is already filled from the order, with the customer's name and every item tagged **Ordered**.
4. :handshake: **Anything extra needs the customer's OK** – parts the mechanic adds on top are sent to the customer's screen as a **quote** with prices and a countdown. **Accept** or **Decline**.
5. :receipt: **Installation and the bill** work as usual. The customer is notified when the order is done.

> :lock: The server refuses any installed part that isn't in the order or approved by the customer – even step by step.

|   |   |   |
|:-:|:-:|:-:|
| <img width="1362" height="1078" alt="image" src="https://github.com/user-attachments/assets/f8efd17c-654d-4abf-a1a5-9d07aba35c62" />
 | <img width="1342" height="1070" alt="image" src="https://github.com/user-attachments/assets/2c48df03-b51d-4f99-92ab-3133e17d0f01" />
 |  |

---

## :moneybag: Economy

- :shopping_cart: **Supplier** with three delivery modes:

  | Mode | Price | Delivery |
  |---|---|---|
  | Instant | 100 % | straight into the storage |
  | Delayed | 85 % | after 15 minutes |
  | Supply run | 65 % | mechanics drive a van to the port and load the crates by hand |

  Daily limits, grade-restricted items – and crates can be **stolen from an unlocked van**.
- :receipt: **Itemized bills** prefilled from the work actually done (labor + parts with markup), mechanic commission, pay by cash or bank. Unpaid bills survive a reconnect (`/mechbills`).
- :recycle: **Crafting** – replaced parts give salvage (scrap metal, aluminium, rubber, plastic, electronics, used oil). 26 recipes, each with an animated bench scene.
- :fuelpump: **Public repair stations** – paid self-service repair, optionally only when no mechanic is on duty.

<img width="1507" height="952" alt="image" src="https://github.com/user-attachments/assets/c85ee3f9-2477-472f-af28-11c800f37f5d" />


---

## :articulated_lorry: Field work – <kbd>F6</kbd> / radial menu

- :raised_hands: **Push**, :arrows_counterclockwise: **flip** and :unlock: **unlock with a slim jim** (fail chance + car alarm)
- :camera_flash: **Impound** with photos
- :link: **Flatbed towing** with a real winch – lower the bed, hook the cable, the car slides up, strap the wheels
- :battery: **Jump start** with visible jumper cables
- :busts_in_silhouette: **5 NPC mission types** – towing, dead battery, flat tyre, out of fuel, scrapping a wreck. The customer waits by the car, watches you work and pays you in hand.
- :construction: **Placeable props** – traffic cones, road barriers, work signs, toolbox

---

## :building_construction: Workshops built in game

- **Unlimited workshops**, several jobs can share one.
- Admin creator `/mechanicadmin` with a live ghost preview – place duty, boss menu, storage, supply delivery, computer, workbench, payment terminal, service vehicles, bays, car lifts and public repair stations. **No coordinates in config files.**
- :closed_lock_with_key: **Permission matrix per job grade** – 17 permissions edited by the boss in a clean UI.
- Duty system, workshop account through your framework's society, deposits at the computer.

<details>
<summary>📦 All 86 items (images included)</summary>

All items use the `mech_` prefix and are mapped in the config, so you can rename them.

- **Service:** engine oil, oil filter, air filter, fuel filter, spark plugs, coolant, brake fluid, transmission fluid, brake pads, tyre, timing belt
- **Core parts:** engine parts, transmission parts, clutch kit, radiator, alternator, car battery, fuel pump, brake discs, shock absorber, turbocharger, EV battery module, EV motor, EV coolant
- **Body:** door, hood, trunk lid, bumper, glass, headlight, wheel, body panel
- **Tools:** OBD scanner, toolbox, impact wrench, car jack, jump starter, slim jim, tuning laptop, spray gun
- **Kits:** repair kit, advanced repair kit, emergency patch kit, cleaning kit
- **Materials:** scrap metal, aluminium, rubber, plastic, electronics, used oil
- **Tuning:** engine, brake, transmission, suspension and armor stages, turbo kit, paint, vinyl, body kit parts, rims, tyre smoke kit, xenon kit, neon kit, window tint, interior parts, horn, plate kit
- **Other:** service book, supply crate, traffic cone, road barrier, work sign

</details>

---


# :books: Documentation

- [1. Highlights](#1-highlights)
- [2. Requirements & compatibility](#2-requirements--compatibility)
- [3. Installation](#3-installation)
- [4. Feature documentation](#4-feature-documentation)
  - [4.1 Workshops, jobs & the in-game creator](#41-workshops-jobs--the-in-game-creator)
  - [4.2 Grades & permissions](#42-grades--permissions)
  - [4.3 Duty](#43-duty)
  - [4.4 Realistic vehicle model](#44-realistic-vehicle-model)
  - [4.5 Diagnostics](#45-diagnostics)
  - [4.6 Repair workflow](#46-repair-workflow)
  - [4.7 Lifts & jacks](#47-lifts--jacks)
  - [4.8 Repair kits & quick repairs](#48-repair-kits--quick-repairs)
  - [4.9 Public repair stations](#49-public-repair-stations)
  - [4.10 Service book & history](#410-service-book--history)
  - [4.11 Tuning](#411-tuning)
  - [4.12 Supplier, ordering & supply runs](#412-supplier-ordering--supply-runs)
  - [4.13 Crafting](#413-crafting)
  - [4.14 Billing](#414-billing)
  - [4.15 Mechanic menu (F6 / radial)](#415-mechanic-menu-f6--radial)
  - [4.16 NPC missions](#416-npc-missions)
  - [4.17 Placeable props](#417-placeable-props)
  - [4.18 Workshop account, deposit & service vehicles](#418-workshop-account-deposit--service-vehicles)
  - [4.19 Stolen parts, quality & origin](#419-stolen-parts-quality--origin)
  - [4.20 Illegal DLC integration (overview)](#420-illegal-dlc-integration-overview)
  - [4.21 Animations system](#421-animations-system)
  - [4.22 Admin commands](#422-admin-commands)
- [5. UI (NUI views)](#5-ui-nui-views)
- [6. Configuration reference](#6-configuration-reference)
  - [6.1 config.lua – general](#61-configlua--general)
  - [6.2 configs/client.lua – client hooks](#62-configsclientlua--client-hooks)
  - [6.3 configs/parts.lua – vehicle model](#63-configspartslua--vehicle-model)
  - [6.4 configs/effects.lua – driving effects](#64-configseffectslua--driving-effects)
  - [6.5 configs/tuning.lua – tuning](#65-configstuninglua--tuning)
  - [6.6 configs/supplier.lua – supplier & billing](#66-configssupplierlua--supplier--billing)
  - [6.7 configs/crafting.lua](#67-configscraftinglua)
  - [6.8 configs/missions.lua](#68-configsmissionslua)
  - [6.9 configs/extras.lua](#69-configsextraslua)
  - [6.10 configs/animations.lua](#610-configsanimationslua)
  - [6.11 BRIDGE/config.lua](#611-bridgeconfiglua)
- [7. Items](#7-items)
- [8. Commands & keybinds](#8-commands--keybinds)
- [9. Exports](#9-exports)
  - [9.1 Server exports – vehicles](#91-server-exports--vehicles)
  - [9.2 Server exports – workshops](#92-server-exports--workshops)
  - [9.3 Client exports](#93-client-exports)
- [10. Open hooks & integration points](#10-open-hooks--integration-points)
  - [10.1 configs/client.lua](#101-configsclientlua)
  - [10.2 server/open.lua](#102-serveropenlua)
  - [10.3 Statebags & GlobalState (read-only for other scripts)](#103-statebags--globalstate-read-only-for-other-scripts)
  - [10.4 Server events (local, AddEventHandler)](#104-server-events-local-addeventhandler)
- [11. Security & performance](#11-security--performance)
- [12. FAQ](#12-faq)
- [13. Version](#13-version)

---

## 1. Highlights

- **Multi-job, multi-workshop.** Admins build unlimited workshops in game (`/mechanicadmin`) with 11 point types. No config coordinates.
- **Permission matrix per job grade.** 17 permissions, which the boss edits in a NUI settings window.
- **Mileage-based condition model.** 11 service parts with km intervals and 13 core parts. Wear depends on vehicle class and tuning. Collisions damage core parts by impact zone.
- **Real driving symptoms.** Power loss, misfires, stalling, limp mode, clutch slip, brake fade, steering pull and wobble, flickering lights, slow cranking, tyre blowouts, smoke and steam.
- **Engine temperature simulation.** Overheating triggers warnings and a power cut, then an engine shutdown. Every minute of overheating damages the engine.
- **Electric vehicle support.** EVs have their own parts (traction battery, electric motor, battery coolant), extra charge drain from a worn battery, and no oil or timing belt.
- **OBD diagnostics.** The mechanic plugs into the OBD port under the dashboard. The React report shows part states, the next service in km, fault codes (P0300, P0520…) and installed tuning. You tick the jobs you want and start the repair.
- **Animated repair workflow.** The mechanic walks to the right spot, opens the hood, lies under the car, drains oil into a drain pan, carries the old part out and the new part in, and test-runs the engine. There are over 40 editable repair scenes.
- **Realistic parts logistics.** Parts don't have to be in your pockets. The workflow pauses on a missing part, a route leads to the storage, and "Take parts for the job" carries a box back to the car.
- **Car lifts and jacks.** Lifts rise smoothly and are synced to everyone. A jack tilts one corner of the car. Some repairs need a lift, a bay or a jack.
- **Performance and visual tuning.** Staged engine, brakes, transmission, suspension, armor and turbo. A full Benny's-style catalogue with a live preview, an orbit camera, a draft cart and step-by-step animated installation. Customers can also pick their tuning themselves in a catalog: the mechanic gets the order, and extras need the customer's approval.
- **Economy.** A supplier with instant, delayed and supply-run delivery (crates can be stolen from the van), daily limits and itemized bills prefilled from the work done. Commission, markups and a labor multiplier are set per workshop.
- **Field work.** An F6 radial or mechanic menu with push, flip, slim-jim unlock, impound with photos, flatbed winch towing, jump start and five NPC mission types with waiting customers.
- **Crafting and recycling.** Replaced parts give salvage materials. 26 workbench recipes, each played as an animated bench scene.
- **Server-authoritative security.** Every action is validated on the server (permission, duty, distance, location, items, minimum work time). The script uses secure events, rate limits, a mileage anti-cheat and plate-spoof protection.

---

## 2. Requirements & compatibility

### Dependencies

| Resource | Required | Notes |
|---|---|---|
| [ox_lib](https://github.com/overextended/ox_lib) | Yes | Menus, callbacks, progress, keybinds, radial, locales |
| [oxmysql](https://github.com/overextended/oxmysql) | Yes | Database (tables are created automatically) |
| Framework | Yes | ESX, QBCore or OX Core (see below) |
| Inventory | Yes | See the inventory table |
| Target | Optional | ox_target / qb-target, or built-in marker mode |
| `pls_bossmenu` | Optional | Default boss-menu hook (`Config.OpenBossMenu`), can be replaced |
| LegacyFuel / ox_fuel | Optional | Supported by the default `Config.SetFuel` hook |
| `pls_mechanic_illegal` | Optional | Paid DLC: crew workshops, stolen parts, chop shop (separate document) |

Game build: the wheel types `open_wheel` (build 2060+), `street` and `track` (2372+) are offered only on those builds.

### Frameworks (`BRIDGE/config.lua`)

| Framework | `BRIDGE.Framework` | Society account | Garage vehicle properties (tuning save) |
|---|---|---|---|
| ESX (Legacy; `BRIDGE.ESXOld = true` for old ESX) | `"ESX"` | `esx_society` + `esx_addonaccount` (`society_<job>`) | `owned_vehicles.vehicle` |
| QBCore | `"QB"` | `qb-banking` (new) or `qb-management` (old) | `player_vehicles.mods` |
| OX Core | `"OX"` | Not implemented in the bridge – edit `BRIDGE/server/framework.lua` | Not implemented – edit the bridge |

The framework is auto-detected (`es_extended` → ESX, `qb-core` → QB, `ox_core` → OX), and the auto-detected value overrides the manual setting. The bridge files are open (escrow-ignored), so you can adapt them to other cores.

### Inventories (`BRIDGE.Inventory`)

| Inventory | Value | Items / usable items | Item metadata (stolen parts) | Storage stock count | Quick take from storage |
|---|---|---|---|---|---|
| ox_inventory | `ox_inventory` | Yes (client export) | Yes | Yes | Yes |
| qb-inventory | `qb_inventory` | Yes | Yes | Yes (PLS stashes with `BRIDGE.QBStashesReplaceByPLS = true`, or qb-inventory 2.x stashes) | Yes |
| Quasar (qs-inventory) | `quasar_inventory` | Yes | Yes | Yes | No – the mechanic opens the storage |
| codem-inventory | `codem` | Yes | No (all parts count as clean) | No | No |
| core_inventory | `core` | Stashes only | No | No | No |

Without stash support, parts fetching still works: the mechanic opens the storage, takes the parts himself and continues the work. The start of a job is never refused because the stock is unknown.

### Target systems

| Mode | Setting |
|---|---|
| ox_target | `BRIDGE.Target = "ox_target"` |
| qb-target | `BRIDGE.Target = "qb_target"` |
| Markers (no target) | `BRIDGE.UseMarkers = true` (optional `BRIDGE.UseDrawText` 3D text, `BRIDGE.DrawText = "[ E ]"`). Vehicle interactions open with `BRIDGE.VehicleInteractKey` (default `G`). `BRIDGE.AllowModelTargetToKeypress` replaces model targets with markers. |

### Languages

`locales/en.json` and `locales/cs.json` (English and Czech, 1 213 strings each, including all NUI texts). The language follows the ox_lib locale convar (`setr ox:locale "en"` / `"cs"`). Item labels and descriptions come from your inventory item definitions.

### Escrow / open files

The resource ships escrow-protected. These files stay **open** for editing:

| Open file | Content |
|---|---|
| `BRIDGE/config.lua`, `BRIDGE/client/*.lua`, `BRIDGE/server/*.lua` | Framework, inventory, target, notifications |
| `config.lua`, `configs/*.lua` | All configuration |
| `secure.lua` | Secure event helper |
| `server/open.lua` | Server hooks (impound, paid bill, logs, custom crafting) |
| `INSTALL/*.lua` | Item definitions |

The NUI is a prebuilt React app (`web/dist`). Its source lives in `web/` (React, Vite and Mantine). Use `npm install`, then `npm run dev` for a browser preview with mock data or `npm run build` to rebuild.

---

## 3. Installation

:arrow_forward: **[Watch: Installation tutorial]([https://www.youtube.com/watch?v=VIDEO_5_INSTALL_TUTORIAL](https://youtu.be/1Sn_eW1SCns))**

1. **Copy the resource.** Place `pls_mechanic` into your resources folder.
2. **Add the items.**
   - *ox_inventory*: copy the `items` table from `INSTALL/items.lua` into `ox_inventory/data/items.lua`. Usable items already carry `client = { export = 'pls_mechanic.useItem' }` and `consume = 0`, because the script removes items itself.
   - *QBCore*: copy the `qbcore` table from `INSTALL/items.lua` into `qb-core/shared/items.lua`. The script registers usable items itself for every inventory except ox_inventory.
   - Only copy the contents of the table. The `local items =` wrapper exists only for the editor.
3. **Copy the images.** Copy `INSTALL/images/*.png` (86 images) into your inventory image folder and set `Config.ImagePath` in `config.lua`:
   - ox_inventory: `"nui://ox_inventory/web/images/%s.png"` (default)
   - qb-inventory: `"nui://qb-inventory/html/images/%s.png"`
4. **Database.** Five tables are created automatically on start. `INSTALL/install.sql` is provided for a manual install:
   `pls_mechanic_shops`, `pls_mechanic_vehicles`, `pls_mechanic_history`, `pls_mechanic_bills`, `pls_mechanic_orders`.
5. **Configure the bridge.** In `BRIDGE/config.lua` set the inventory, the target (or `UseMarkers`) and, if needed, `BRIDGE.ESXOld` and the notification function. The framework is auto-detected.
6. **Set the start order** in `server.cfg`:
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure es_extended        # or qb-core / ox_core
   ensure ox_inventory       # your inventory
   ensure ox_target          # your target (optional)
   ensure pls_mechanic
   ensure pls_mechanic_illegal   # optional DLC, always after pls_mechanic
   ```
7. **Create the society account.** Bills, deposits, supplier payments and repair stations use the society account of the **first job** of each workshop (ESX: `society_<job>` in `addon_account`, shared = 1; QB: the job account in qb-banking or qb-management). `/mechsociety` prints a diagnosis to the server console.
8. **Build the first workshop.** Join as an admin (`group.admin`), run `/mechanicadmin` and choose **Create workshop**. Enter the name and the jobs (comma separated), set the blip, then place the points: duty, boss menu, storage, supply delivery, computer, workbench, payment terminal, service vehicles, bays, car lifts and repair stations. Press **Save**.
9. **Hook your systems (optional).** In `configs/client.lua` set the boss menu, fuel, vehicle keys and police dispatch. In `server/open.lua` set impound, paid-bill actions, logs and custom crafting.

---

## 4. Feature documentation

### 4.1 Workshops, jobs & the in-game creator

- There is no limit on the number of workshops. Each workshop has a name, **up to 10 jobs**, an optional map blip, **up to 150 points**, a permission matrix and its own settings (prices, commission, supply modes).
- Several jobs can share one workshop. A player works for the workshop where he clocked in. The workshop account is the society account of the **first** job.
- `/mechanicadmin` (ace group `Config.AdminGroup`, default `group.admin`) opens the **creator**. Every change stays in a local draft until you press **Save**, and the server validates everything again. In the creator you can:
  - create, edit and delete workshops, change the name, jobs and workshop type (legal or illegal),
  - edit the blip: enabled, sprite, colour, scale, and a position that is either "here" or automatically the first point,
  - add points with a live ghost preview (`E` confirm, scroll or `←` `→` rotate with Shift for fine steps, `↑` `↓` radius from 0.5 to 15 m, `Backspace` cancel), then move, re-radius, teleport to, edit the fields of, or delete them,
  - see floating labels while the creator is open (type, #, radius, heading),
  - open the boss settings of the workshop, or reset its permissions to the defaults,
  - create illegal workshops and set their owner (only while the illegal DLC runs).
- Workshops are synced to clients through `GlobalState.pls_mechanic_shops`. Targets or markers and blips are rebuilt live when a workshop changes.

#### Point types

| Type | Label | Purpose | Radius | Multiple | Workshop kinds | Extra fields |
|---|---|---|---|---|---|---|
| `duty` | Duty | Clock in / clock out (perm `duty`) | 1.5 | No | legal | – |
| `boss` | Boss menu | Opens your boss menu via `Config.OpenBossMenu` (perm `bossmenu`) | 1.5 | No | legal | – |
| `storage` | Storage | Workshop stash (perm `storage`), "Take parts for the job" | 1.5 | No | legal, illegal | – |
| `supply` | Supply delivery | Unloading supply-run crates, "Deliver crates" (perm `supply_run`) | 2.5 | No | legal | – |
| `computer` | Computer | Supplier (`order`), start or cancel a supply run (`supply_run`), deposit to the workshop account (employees), workshop settings (`manage_shop`) | 1.5 | Yes | legal | – |
| `workbench` | Workbench | Crafting (perm `craft`) | 1.5 | Yes | legal, illegal | – |
| `billing` | Payment terminal | Customers pay their pending bills of this workshop | 1.5 | Yes | legal, illegal | – |
| `garage` | Service vehicles | Spawn and return service vehicles (perm `duty`), supply van spawn | 2.0 | No | legal | – |
| `bay` | Bay | Repair location for `bay` repairs, tuning (perm `tuning_visual` or `tuning_performance`) | 4.0 | Yes | legal, illegal | `bayType`: `repair` / `tuning` / `both` (default `both`) |
| `lift` | Car lift | Raise / lower a vehicle (perm `service`) | 4.0 | Yes | legal, illegal | `height` (m, 0.5–2.5, default 1.8) |
| `station` | Repair station | Public paid self-service repair | 4.0 | Yes | legal | `price` (500), `duration` s (20), `repairs` (engine / body / service / core, default engine + body), `onlyWithoutMechanic` (true), `jobs` (comma separated, empty = everyone) |

Other resources can add their own point types with the `RegisterPointType` export (for example the chop and laptop points of the illegal DLC).

### 4.2 Grades & permissions

A legal workshop has one permission matrix **per job and per grade**. The boss edits it in **Computer → Workshop settings → Permissions**. You can toggle a whole row or a whole grade column at once. A boss can never remove `manage_shop` from his own grade.

| Permission | Allows |
|---|---|
| `duty` | Clock in and out, spawn service vehicles |
| `diagnose` | OBD diagnostics, reopening the last report, reading the service book of any plate (legal workshops) |
| `service` | Service-part jobs, battery replacement, car lift raise/lower, car jack |
| `repair_core` | Core-part repairs (engine, transmission, clutch, radiator, alternator, fuel pump, brake discs, suspension, alignment, turbo, EV battery, EV motor) |
| `repair_body` | Bodywork repairs (`Config.BodyRepairPermission`) |
| `tuning_performance` | Performance tuning (engine, brakes, transmission, suspension, armor, turbo) |
| `tuning_visual` | Visual tuning (paint, body kit, wheels, interior, lights, other) |
| `storage` | Open the workshop storage, quick-take parts for a job |
| `craft` | Workbench crafting |
| `order` | Supplier catalogue and orders |
| `supply_run` | Start and cancel supply runs, unload and deliver crates |
| `billing` | Create bills for customers |
| `tow` | Push, flip, slim-jim unlock, flatbed load/unload |
| `impound` | Impound vehicles |
| `missions` | NPC missions |
| `manage_shop` | Workshop settings (permissions, prices, commission, supply modes, bills and orders logs) |
| `bossmenu` | Boss-menu point |

**Default matrix for a new workshop** (`Config.DefaultPermissions`). A grade without an entry uses the closest lower configured grade. **The highest grade of the job always gets every permission.**

| Permission | Grade 0 | Grade 1 | Grade 2 | Grade 3 | Highest grade |
|---|:-:|:-:|:-:|:-:|:-:|
| duty | ✔ | ✔ | ✔ | ✔ | ✔ |
| diagnose | ✔ | ✔ | ✔ | ✔ | ✔ |
| service | ✔ | ✔ | ✔ | ✔ | ✔ |
| repair_core | | | ✔ | ✔ | ✔ |
| repair_body | | ✔ | ✔ | ✔ | ✔ |
| tuning_performance | | | | ✔ | ✔ |
| tuning_visual | | | ✔ | ✔ | ✔ |
| storage | ✔ | ✔ | ✔ | ✔ | ✔ |
| craft | | ✔ | ✔ | ✔ | ✔ |
| order | | | | ✔ | ✔ |
| supply_run | | | ✔ | ✔ | ✔ |
| billing | | ✔ | ✔ | ✔ | ✔ |
| tow | ✔ | ✔ | ✔ | ✔ | ✔ |
| impound | | | ✔ | ✔ | ✔ |
| missions | ✔ | ✔ | ✔ | ✔ | ✔ |
| manage_shop | | | | | ✔ |
| bossmenu | | | | | ✔ |

### 4.3 Duty

- Players clock in and out at the **duty** point. If a workshop has no duty point, the server skips the distance check.
- With `Config.RequireDuty = true` (default), every job action requires being on duty **in that workshop**. The exceptions are `duty`, `bossmenu` and `manage_shop`.
- With `Config.RequireDuty = false`, the player's first workshop (by job) counts as his current workshop.
- Duty is stored in the player statebag `pls_mechanic_duty` (shop id or `false`). The server re-checks it every minute and immediately after the workshop jobs or permissions change. A player who loses the job or the `duty` permission is clocked out.
- Going off duty cancels an active NPC mission. The F6 menu and the radial item are only available while on duty (or inside your own illegal workshop).

### 4.4 Realistic vehicle model

Every land vehicle gets a condition record. Excluded classes (`Config.ExcludedClasses`: cycles, boats, helicopters, planes, trains) and the server vehicle types boat, heli, plane, submarine, train and trailer have no parts system.

**Data per vehicle:** mileage (km), service parts (life %), core parts (health %), EV flag, owned flag, part origin (stolen parts) and modifiers from other resources.

- **Owned vehicles** are stored in `pls_mechanic_vehicles`. They are batch-saved every `saveInterval` (5 min) and immediately when the driver leaves, the vehicle is deleted, the player drops, the resource stops or txAdmin shuts down.
- **Not-owned (NPC or stolen) vehicles** live in memory. They are forgotten after `npcCacheHours` (6 h) without activity.
- Part states follow `Config.PartStates`: above **70 %** Optimal, above **40 %** Worn, above **15 %** Critical, otherwise Failed.

#### Mileage

- The driver's client counts distance and reports it at least every **60 s** or every **1 km** (`syncInterval`, `syncDistance`). A final flush is sent when the driver leaves the vehicle.
- The server clamps every report to what is physically possible at `maxSpeed` **450 km/h** (anti-cheat).
- With `Config.ShowMileage` an odometer (`ODO 12 345.6 km`) is drawn above the minimap while driving. The unit follows `Config.MileageUnit` (`km` or `mi`).

#### Service parts (wear by km)

Life drops by `km × classWear × tuningWear × partWear / interval × 100`. After life reaches 0, every further km damages the linked core parts (`damages`, % per km). The **timing belt snaps** when it reaches 0 and the engine fails immediately.

| Key | Part | Vehicle | Interval (km) | Items | Tools | Damages when overdue (%/km) | Location | Access | Time (s) | Labor ($) | OBD |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `oil` | Engine oil & filter | ICE | 800 | engine_oil, oil_filter | toolbox | engine 0.05, turbo 0.05 | anywhere | hood | 20 | 150 | P0520 |
| `air_filter` | Air filter | ICE | 1 500 | air_filter | – | engine 0.02 | anywhere | hood | 8 | 50 | P0101 |
| `fuel_filter` | Fuel filter | ICE | 2 000 | fuel_filter | toolbox | fuel_pump 0.05 | anywhere | hood | 12 | 80 | P0171 |
| `spark_plugs` | Spark plugs | ICE | 2 500 | spark_plugs | toolbox | engine 0.03 | anywhere | hood | 15 | 100 | P0301 |
| `coolant` | Coolant | ICE | 3 000 | coolant | – | radiator 0.05, engine 0.02 | anywhere | hood | 10 | 60 | P0128 |
| `brake_fluid` | Brake fluid | All | 3 000 | brake_fluid | – | brakes 0.04 | anywhere | hood | 12 | 60 | – |
| `transmission_fluid` | Transmission fluid | ICE | 4 000 | transmission_fluid | toolbox | transmission 0.04, clutch 0.04 | bay | under | 20 | 120 | P0711 |
| `brake_pads` | Brake pads | All | 1 500 | 2× brake_pads | toolbox, impact_wrench | brakes 0.08 | lift_or_jack | wheel | 25 | 150 | – |
| `tyres` | Tyres | All | 2 000 | 4× tyre | impact_wrench | alignment 0.02 | lift_or_jack | wheel | 30 | 120 | – |
| `timing_belt` | Timing belt | ICE | 6 000 | timing_belt | toolbox | snaps → engine fails | bay | hood | 45 | 300 | P0016 |
| `ev_coolant` | Battery coolant | EV | 4 000 | ev_coolant | – | ev_battery 0.04 | anywhere | hood | 15 | 80 | P0C73 |

All service parts need the `service` permission. Replaced parts give **salvage**: used oil (oil change), plastic (air and fuel filter), scrap metal (spark plugs, brake pads), 4× rubber (tyres) and rubber (timing belt).

#### Core parts (collisions and neglected service)

| Key | Part | Vehicle | Items | Tools | Location | Access | Time (s) | Labor ($) | Permission | OBD | Salvage |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `engine` | Engine | ICE | engine_parts | toolbox, impact_wrench | bay | hood | 90 | 1 500 | repair_core | P0300 | 3 scrap metal, 2 aluminium |
| `transmission` | Transmission | ICE | transmission_parts | toolbox, impact_wrench | lift | under | 80 | 1 200 | repair_core | P0700 | 3 scrap metal, 1 aluminium |
| `clutch` | Clutch | ICE | clutch_kit | toolbox, impact_wrench | lift | under | 60 | 800 | repair_core | P0806 | 2 scrap metal |
| `radiator` | Radiator | ICE | radiator | toolbox | bay | hood | 35 | 400 | repair_core | P0217 | 2 aluminium |
| `alternator` | Alternator | ICE | alternator | toolbox | bay | hood | 30 | 350 | repair_core | P0562 | electronics, scrap metal |
| `battery` | Battery | All | car_battery | – | anywhere | hood | 12 | 80 | service | P0560 | scrap metal, plastic |
| `fuel_pump` | Fuel pump | ICE | fuel_pump | toolbox | lift | under | 40 | 450 | repair_core | P0087 | electronics |
| `brakes` | Brake discs | All | 2× brake_discs | toolbox, impact_wrench | lift_or_jack | wheel | 40 | 400 | repair_core | C0035 | 2 scrap metal |
| `suspension` | Suspension | All | 4× shock_absorber | toolbox, impact_wrench | lift | wheel | 60 | 600 | repair_core | – | 2 scrap metal |
| `alignment` | Wheel alignment | All | – | toolbox | bay | wheel | 25 | 250 | repair_core | – | – |
| `turbo` | Turbocharger (only with turbo installed) | ICE | turbocharger | toolbox | bay | hood | 45 | 700 | repair_core | P0299 | 2 scrap metal, 1 aluminium |
| `ev_battery` | Traction battery | EV | 2× ev_battery_module | toolbox | lift | under | 90 | 1 500 | repair_core | P0A80 | 3 electronics |
| `ev_motor` | Electric motor | EV | ev_motor | toolbox, impact_wrench | lift | under | 80 | 1 300 | repair_core | – | 2 electronics, 2 scrap metal |

**Location rules:** `anywhere`. `bay` means a repair bay (bay type `repair` or `both`) **or** a lift. `lift` means the vehicle must be on a lift. `lift_or_jack` means on a lift or jacked up at the right wheel.

**Extra wear per driven km (server, `Config.Effects.Wear`):**
- Natural ageing: clutch 0.002, suspension 0.0015, battery 0.004 and ev_battery 0.001 (% per km × class wear).
- A radiator in critical or failed state damages the engine by 0.01 or 0.03 % per km.
- A worn, critical or failed alternator drains the battery by 0.01, 0.04 or 0.12 % per km.
- Overheating costs `engineDamagePerMinute` = 2 % engine health per minute.

**Wear multipliers:**
- Vehicle class (`Config.ClassWear`, 0.8 for industrial up to 1.6 for open wheel).
- Performance tuning (`Config.TuningWear`): each engine level adds +15 % wear to oil, spark plugs, air filter and timing belt. Each transmission level adds +15 % to transmission fluid. Each brake level reduces brake-pad wear by −10 %. A turbo adds +25 % oil wear.
- Stolen parts of unknown origin wear **×1.5**.

#### Collisions

The driver's client measures the speed lost in an impact (200 ms window, 750 ms cooldown) and the impact zone (front, rear, left, right). Impacts below **8 km/h** are ignored. Core damage = `severity × zone factor × multiplier (1.0) × 0.5`:

| Zone | Affected core parts (factor) |
|---|---|
| Front | engine 0.6, radiator 1.0, alternator 0.7, battery 0.3, alignment 0.4, suspension 0.3, ev_motor 0.4, ev_battery 0.2 |
| Rear | fuel_pump 0.8, suspension 0.4, transmission 0.2, ev_battery 0.4 |
| Left / right | suspension 0.8, alignment 0.8, brakes 0.3 |
| Heavy (≥ 60 km/h) extra | transmission 0.5, clutch 0.3, engine 0.3, ev_motor 0.3 |

#### Body damage

Native GTA damage is detected and repaired **part by part**. A repair fixes only the chosen part: all other damage, including deformation, is snapshotted and restored. The body parts are 4 doors, the hood, the trunk lid, 8 windows, front and rear bumper, left and right headlight, up to 6 tyres, up to 6 missing wheels, the fuel tank (tank health < 700, not on EVs) and bodywork deformation (body health < 950 or measured deformation). Bodywork needs 1, 2 or 3 body panels depending on body health (< 900 / < 700 / < 400).

| Body part | Item | Tool | Location | Time (s) | Labor ($) |
|---|---|---|---|---|---|
| Door | car_door | toolbox | anywhere | 20 | 200 |
| Hood | car_hood | toolbox | anywhere | 20 | 200 |
| Trunk lid | car_trunk | toolbox | anywhere | 20 | 200 |
| Window | car_glass | toolbox | anywhere | 15 | 150 |
| Bumper | car_bumper | toolbox | anywhere | 15 | 150 |
| Headlight | car_headlight | toolbox | anywhere | 8 | 80 |
| Tyre | tyre | impact_wrench | lift_or_jack | 12 | 60 |
| Wheel | car_wheel | impact_wrench | lift_or_jack | 15 | 80 |
| Fuel tank | body_panel | toolbox | bay | 25 | 250 |
| Bodywork | 1–3× body_panel | toolbox | bay | 40 | 400 |

#### Electric vehicles

EVs are recognised by model (`Config.ElectricVehicles`, 20 models by default, including voltic, raiden, cyclone, tezeract, neon, khamelion, iwagen, omnisegt, virtue, buffalo5, surge and caddy). They have:
- only the parts marked `ev` or `all` (no oil, filters, spark plugs, coolant, timing belt, clutch, radiator, alternator, fuel pump or turbo),
- extra battery drain from a worn traction battery (`evDrain`, fuel % per km, applied through `Config.SetFuel`),
- no temperature simulation, no revving sounds during tuning calibration, and no turbo in tuning.

#### OBD fault codes

| Code | Description | Part |
|---|---|---|
| P0016 | Crankshaft / camshaft position correlation | Timing belt |
| P0087 | Fuel rail / system pressure too low | Fuel pump |
| P0101 | Mass air flow circuit range / performance | Air filter |
| P0128 | Coolant temperature below thermostat regulating temperature | Coolant |
| P0171 | System too lean | Fuel filter |
| P0217 | Engine overheat condition | Radiator |
| P0299 | Turbocharger underboost | Turbocharger |
| P0300 | Random / multiple cylinder misfire detected | Engine |
| P0301 | Cylinder 1 misfire detected | Spark plugs |
| P0520 | Engine oil pressure sensor circuit | Engine oil |
| P0560 | System voltage malfunction | Battery |
| P0562 | System voltage low | Alternator |
| P0700 | Transmission control system malfunction | Transmission |
| P0711 | Transmission fluid temperature sensor range / performance | Transmission fluid |
| P0806 | Clutch position sensor circuit range / performance | Clutch |
| P0A80 | Replace hybrid / EV battery pack | Traction battery |
| P0C73 | Motor electronics coolant pump | Battery coolant |
| C0035 | Left front wheel speed sensor circuit | Brake discs |

The diagnostics report lists a part's code as soon as the part is no longer Optimal. The illegal DLC can add its own findings (for example illegal modifications) to the fault code list.

#### Effects on driving

Effects apply only to the **driver**, and only while `Config.Effects.Enabled = true`. The driver gets dashboard warnings when he gets in (core parts Critical or worse, service parts Failed) and when a part gets worse while driving (core parts Worn or worse, service parts Critical or worse).

| Part | Worn | Critical | Failed / empty |
|---|---|---|---|
| Engine | power 90 % | power 70 %, smoke, stalls below 30 km/h, misfires | won't start, smoke |
| Transmission | slower shifts, power 95 % | shifts 45 %, power 85 %, limp mode 70 km/h | engine runs, the car won't drive |
| Clutch | slips above 90 % throttle | slips above 60 % throttle, slower shifts | the car won't drive |
| Radiator | cooling 80 % | cooling 55 % | cooling 30 % |
| Alternator | lights dim and flicker | stronger dimming and flicker | lights 45 %, heavy flicker (and the battery drains) |
| Battery | slow cranking | 2 s cranking, 35 % failed starts, dim lights | won't start |
| Fuel pump | stutter at high rpm | stronger stutter, stalling | won't start |
| Brake discs | brakes 85 % | brakes 60 % | brakes 30 % |
| Suspension | light wobble | wobble, grip 95 % | strong wobble, grip 88 %, max 110 km/h |
| Alignment | slight pull | pull | strong pull, grip 95 % |
| Turbo | power 95 % | power 85 %, stutter | power 78 % |
| EV battery | power 95 %, extra drain | power 80 %, more drain, max 100 km/h | won't start |
| EV motor | power 90 % | power 70 %, power cuts | won't start |
| Engine oil | – | – | failed: power 97 %; empty: power 90 % + stutter |
| Air filter | – | power 96 % | power 90 % |
| Fuel filter | – | – | stutter |
| Spark plugs | – | misfires | power 92 %, misfires |
| Coolant | – | cooling 85 % | cooling 65 % (empty 40 %) |
| Brake fluid | – | brakes 90 % | brakes 75 % |
| Transmission fluid | – | – | slower shifts |
| Brake pads | – | brakes 90 % | brakes 70 % |
| Tyres | grip 97 % | grip 90 % | grip 82 %; empty: grip 75 % + blowouts above 120 km/h |
| Timing belt | – | – | empty: won't start |
| Battery coolant | – | – | power 95 % (empty 85 %) |

Steering pull and wobble apply above 25 km/h, and only while the driver isn't steering. Smoke and steam particles are networked, so other players see them.

**Engine temperature simulation** (combustion engines): normal 90 °C; warning at 110 °C; at 120 °C steam comes from the engine bay and power drops to 55 %; at 130 °C the engine shuts down and can't be restarted until it cools to 105 °C. Cooling depends on the radiator and coolant state, airflow (speed) and load.

#### New vehicles, NPC and stolen cars

| Situation | Starting condition |
|---|---|
| Owned vehicle seen for the first time | Brand new: 5–60 km, every part 100 % |
| Not-owned vehicle (NPC, stolen) driven for the first time | Random used car: 20 000–250 000 km, service parts worn 10–90 %, core parts damaged 0–35 %. Higher mileage means a worse condition, some previous owners serviced recently, and neglected service has already marked the linked core parts. Never worse than core 45 % (Worn) or service 15 %. |
| Not-owned vehicle registered as owned within 300 s of first use and with < 5 km driven | Treated as a shop purchase and reset to brand new |
| Not-owned vehicle registered later (stolen and then registered) | Keeps its used condition |
| `exports.pls_mechanic:SetVehicleNew(plate)` | Brand new. Works before the first drive (valid for 1 hour) and after it |

A vehicle shop that writes the owner shortly after spawning is detected automatically. For 100 % reliability, call `SetVehicleNew` after the purchase (see Exports).

#### Plates & plate-spoof protection

Every vehicle entity has a **trusted plate**: the plate seen first. A newly spawned vehicle settles 10 s after it gets an owner client, so garage scripts can still set the plate. After that, only the server can change it (`SetTrustedPlate`, plate aliases). If the owner client changes the plate text to another player's plate, the change is ignored: repairs, wear, tuning records and refunds, impound and the service book all use the trusted plate. Fake plates (illegal DLC) are resolved through plate aliases.

### 4.5 Diagnostics

1. **Start** in any of these ways:
   - the vehicle target **Diagnose vehicle** (hood, engine or driver door),
   - the mechanic menu **Diagnose**,
   - using the **OBD Scanner** item near a vehicle or inside it.

   Requirements: the `diagnose` permission, being on duty and an OBD scanner in the inventory.
2. **Scan scene.** The windows roll up and the mechanic walks to the driver door, opens it, kneels and plugs the connector (2 s). He then reads the control unit on a tablet with scanner beeps (5 s). From the driver seat, the scan takes 7 s of tablet reading.
3. The **diagnostics report** NUI opens with these tabs:
   - **Service parts:** life %, state, next service in km (or "overdue by"), required items (have / need) and tools, location requirement.
   - **Core parts:** health %, state, requirements.
   - **Bodywork:** every damaged body part.
   - **Fault codes:** OBD codes of non-optimal parts, plus DLC findings.
   - **Tuning:** engine, brakes, transmission, suspension and armor level, turbo.
   - A header with plate, model, class, mileage, EV badge and engine, body and fuel-tank health gauges.

   Parts you can't repair (missing permission) are marked. Parts installed from stolen items show an **unknown origin** badge. Quick selection buttons are **Select all** and **Select worn & critical**.
4. **Start repair** runs the chosen jobs as one workflow (4.6).
5. **Reopen.** The last report of a vehicle can be reopened without a new scan for `Config.DiagnosticsReopen` minutes (10) with fresh data. Use the **Open last diagnostics** target, the mechanic menu, or the scanner item, which then offers "New diagnostics" or "Open last diagnostics".

### 4.6 Repair workflow

- **Preflight.** Before the start, the client checks every selected step: permission, location (bay, lift, jack), tools and parts. When parts fetching is on, the start is refused only if a part or tool is in neither the inventory nor the workshop storage. All problems are listed at once.
- **Order.** Jobs are sorted by access: fluids and filters first, then hood → trunk → under → wheels. Bodywork comes last and deformation is the very last step.
- **Per step:**
  - The client asks the server to **begin**. The server validates the step and starts a timer.
  - The **animated scene** plays: walking to the spot, opening the door or hood, work phases with animations, hand props, sounds and particles, placing the drain pan, carrying the old part out and fetching the new part from the toolbox.
  - The server **finishes** the step. It validates everything again and requires at least **90 %** of the configured duration.
  - The part condition is updated and the natives are applied.
  - A test run of the engine follows where configured (battery, alternator, spark plugs, fuel filter, timing belt, engine…).
  - Old parts left on the ground are collected.
- **Overlay.** A workflow overlay (NUI) shows every step with its status (waiting, in progress, done, failed, skipped, needs parts), the current phase and the result.
- **Toolbox and props.** With a toolbox in the inventory, the mechanic puts a toolbox next to the vehicle for the whole workflow (`Config.Animations.Settings.toolbox`). On a lift above 1.6 m, the mechanic works standing under the car instead of lying down.
- **Cancel.** Press `X` (`Config.Keys.cancel`) or use the vehicle target **Cancel repair**. The workflow is also stopped when the mechanic gets further than 15 m from the car.
- **Result.** Each finished step:
  - consumes the parts according to the workshop rules (4.19),
  - gives salvage,
  - writes a work-log entry (it prefills the bill),
  - writes a service-book record,
  - triggers the server event `pls_mechanic:server:repair:done`.

#### Parts fetching (`Config.Fetch`)

Heavy parts don't have to be carried at the start of a repair or tuning job.
- A step without its parts or tools **pauses**. The overlay shows what is missing (have, need, in storage), and a route blip leads to the workshop storage (`storageBlip`).
- At the storage point, **Take parts for the job** (`quickTake`) moves exactly the missing parts of the step into the inventory. The mechanic then carries a parts box (`carry = "part_box"`). **Open storage** still works as usual.
- Back at the car, the target **Continue repair** or **Continue tuning** resumes the workflow within `resumeDistance` (4 m).
- Waiting is cancelled after `timeout` (10 min) or when the mechanic gets further than `maxDistance` (120 m).
- `enabled = false` restores the classic behaviour, where everything must be in the inventory before the start.

### 4.7 Lifts & jacks

- **Car lift.**
  - The action is **Raise lift** or **Lower lift** on the lift point and needs the `service` permission. The mechanic presses the panel button.
  - The vehicle must stand on the lift without a driver and without a jack. It is frozen and raised to the point height (default 1.8 m) at 0.35 m/s.
  - All clients see the movement (GlobalState `pls_mech_lift_<shopId>_<pointId>`), with a hydraulic sound. An optional lift prop model is `Config.Props.lift`.
- **Car jack.**
  - Use the **Car Jack** item next to a wheel (within 1.8 m). The `service` permission is required.
  - The mechanic carries the jack to the wheel, slides it under the car and pumps it up. That corner rises 0.16 m (statebag `pls_jack`).
  - The jack item is taken while placed and returned on **Remove jack**. Jacks work only on four-wheel automobiles, not on motorcycles or vehicles on a lift.
- **Driving is blocked** while a vehicle is on a lift or a jack.
- Lifts and jacks satisfy the `lift` and `lift_or_jack` location rules. `lift_or_jack` wheel jobs need the jack on the side of the repaired wheel.

### 4.8 Repair kits & quick repairs

Kits are used from the inventory on the closest vehicle and play an animated scene.

| Kit | Who can use it | Time | Effect |
|---|---|---|---|
| Repair Kit | Anyone | 15 s | Engine health raised to at least 650 |
| Advanced Repair Kit | Mechanics on duty (or crew in their illegal workshop), plus the jobs `police` and `ambulance` | 25 s | Full native repair (engine and body 1000); core parts below 60 % are raised to 60 % |
| Emergency Patch Kit | Anyone | 20 s | Critical or failed core parts raised to 16 % (just above critical), engine made drivable – enough to reach a workshop |
| Cleaning Kit | Anyone | 10 s | Washes dirt off the vehicle |

A kit is refused when the vehicle doesn't need it. Kits used on a vehicle with data are written into the service book, except the cleaning kit.

**Quick repairs** (`Config.QuickRepairs`) are done directly with an item, without diagnostics. They still need the permission of the part:

| Item | Action | Requirement |
|---|---|---|
| Tyre | Replace the closest burst tyre | Jack under that wheel or a lift |
| Wheel | Replace the closest missing wheel | Jack or lift |
| Car Battery | Replace the battery (core part `battery`) | – |

### 4.9 Public repair stations

- An admin places a **station** point and sets its price, duration, repairs (engine, body, service parts, core parts), allowed jobs and "only when no mechanic is on duty".
- The **driver** drives into the station and presses `[E]`, or uses the target. A confirmation shows the repairs and the price.
- Payment is taken as cash first, then bank (`Config.Stations.paymentMethods`). With `societyPayment` the money goes to the workshop society.
- **Service scene:** the engine goes off, the hood opens and a cinematic camera orbits the car. The phases are check-in, diagnostics, repair (sparks and air tools) and final check. The service is already paid and can't be cancelled.
- Service and core parts are set to 100 % with a clean origin. A "Repair station" entry is written to the service book.

### 4.10 Service book & history

- Every repair, kit, tuning job and station service is stored in `pls_mechanic_history`: date, workshop, mechanic, type, label, parts and mileage. Work done in illegal workshops is **never** written.
- **Service Book item.** Anyone holding it can read the history of a vehicle that is next to them (within 10 m).
- **Mechanics with `diagnose`** (legal workshop) can read the book of any plate from the mechanic menu, without the item.
- The **history NUI** shows the plate, model, mileage, last visit and record count, with a filter by type: service, core part, bodywork, repair kit, repair station, tuning.

### 4.11 Tuning

Tuning is opened with the target **Tuning** on a **bay** of type `tuning` or `both` while the vehicle stands in it. It requires `tuning_visual` or `tuning_performance`.

- **Live preview.** Hovering an option previews it on the car. A click adds it to the **Changes** cart. **Revert to installed** undoes a category.
- **Camera.** An orbit camera jumps to the preset of each category (hood, wheel, interior, trunk, under…). Rotate and zoom buttons are available, and the needed doors open automatically. The mechanic's ped can be hidden for the camera (`HidePlayer`).
- **Drafts.** An unconfirmed cart is kept for `DraftMinutes` (15) and restored when tuning is opened on the same vehicle again. Closing the menu reverts everything that wasn't confirmed. If the mechanic disconnects, the new owner of the vehicle reverts the preview.
- **Validation.** Each confirmation is validated on the server: permission, duty, bay, distance (8 m), values, dependencies, tools and materials. At most 60 changes per confirmation, with a 1.5 s cooldown.
- **Prices.** Base price plus the workshop `tuningMarkup` %. The final price goes to the mechanic's work log (billing) and a history entry is written. Owned vehicles' properties are saved to the garage table (`SaveOwnedVehicles`).
- **Step-by-step installation** (`Install.enabled`). After confirmation, every change is installed as its own animated step:
  - the mechanic carries a parts crate or the part itself to the car and unpacks it,
  - he walks to the work spots and works through the phases (for example the gearbox is unbolted and fitted while lying under the car, a caliper is fitted at each front wheel, paint is sprayed on both sides),
  - the part appears on the car, followed by a laptop calibration for engine, transmission and turbo (6 s) and a test: revving, horn, lights, neon, hydraulics,
  - removed parts are left on the ground until the end.

  Each step is confirmed by the server after 90 % of its work time. `X` or the target **Cancel tuning installation** stops the installation, and changes not yet installed stay in the saved cart. With parts fetching, a step without its item pauses exactly like a repair step.

#### Customer catalog (`Config.Tuning.Catalog`)

The customer picks the tuning themselves. **Anybody** standing at a vehicle in a tuning bay gets the target **Tuning catalog**, and ownership of the vehicle is not checked.

- **Catalog.** The same tuning menu opens in customer mode, with live preview, camera, categories and prices including the workshop markup. Item and tool requirements are hidden. **Send order** stores the order on the server and closes the catalog; the preview is reverted, so the car stays as it was.
  - With an order already sent, the customer sees it again in the catalog and can change it, or empty the cart and press **Cancel order**.
  - Only that customer sees the order. Nobody else can replace or cancel it, and each customer can have at most 3 open orders.
  - The vehicle's doors are locked while the catalog is open.
  - Performance parts are offered only with `performance = true`.
  - The catalog works only while a mechanic of the workshop is available (`requireMechanic`), and in illegal workshops only with `illegal = true`.
- **Order.** Mechanics of the workshop with a tuning permission get a notification with the plate, the number of items and the total. They are notified only when the order changed, at most once per 30 s.
  - One order per vehicle.
  - It waits `orderMinutes` (120) from its last activity. An order a mechanic is working on doesn't expire.
  - The catalog can't be opened on a vehicle that is busy (repair, lift, jack, tow, mission).
- **Mechanic.** When the mechanic opens tuning on that vehicle, the cart is prefilled from the order and a banner shows *Order from … · items · total · minutes ago*. Every cart line is tagged **Ordered** or **Needs approval**.
- **Approval** (`approval = true`). Changes the mechanic adds on top of the order are sent to the customer's screen as a **quote**: every item with its price, the extra total, the total and a countdown (`approvalTimeout`, 60 s). The customer can **accept** or **decline** (Esc).
  - The customer has to be online and within `approvalDistance` (30 m).
  - Until the customer answers, the mechanic's confirm button shows *Waiting for the customer's approval…*.
  - The server refuses every confirmation of a change that is neither in the order nor approved, including each step of the step-by-step installation.
  - After a declined or unanswered quote the mechanic has to wait 30 s, and at most 5 quotes can be sent per order.
  - A quote closes when the mechanic leaves the menu.
  - For 15 minutes after an order is done or cancelled, every change on that vehicle still needs the customer's approval.
- **After installation.** Installed items are removed from the order. When the order is empty, the customer is notified. Billing is unchanged: the work log gets the price and the mechanic bills the customer.
- **Locks.** While the customer has the catalog open, mechanics can't open tuning on that vehicle, and the other way round. Open sessions send a heartbeat, so a lock never breaks while somebody is still in the menu.
- **Preview revert.** An unconfirmed preview (catalog or mechanic) is always reverted, even if:
  - someone got into the car,
  - the player disconnected,
  - the session went stale.

  The server leaves a revert statebag on the vehicle, and whoever controls the vehicle next applies it. Paid parts stay.
- **Vehicles without an order.** Tuning works exactly as before.

#### Performance tuning (`tuning_performance`)

| Category | Stages (item, price) | Tool | Removal price | Notes |
|---|---|---|---|---|
| Engine (mod 11) | 1 `engine_stage1` $4 000 · 2 $8 000 · 3 $14 000 · 4 $22 000 | tuning_laptop | $800 | Stage 3 needs transmission ≥ 1, stage 4 needs transmission ≥ 2 |
| Brakes (mod 12) | 1 $2 500 · 2 $5 000 · 3 $8 500 | – | $500 | |
| Transmission (mod 13) | 1 $3 500 · 2 $7 000 · 3 $12 000 | tuning_laptop | $700 | |
| Suspension (mod 15) | 1 $1 500 · 2 $3 000 · 3 $5 000 · 4 $8 000 | – | $400 | |
| Armor (mod 16) | 1 $5 000 · 2 $9 000 · 3 $14 000 · 4 $20 000 · 5 $28 000 | – | $1 000 | |
| Turbo (mod 18, toggle) | `turbo_kit` $15 000 | tuning_laptop | charged on install and removal | Not offered for EVs |

The stage item is consumed on install. On a downgrade, upgrade or return to stock, the removed part is **returned to the mechanic**, but only if this workshop system installed it (anti-duplication). A part installed from a stolen item comes back stolen.

#### Visual tuning (`tuning_visual`, Benny's style)

| Group | Categories |
|---|---|
| Paint | Primary, secondary, pearlescent and wheel colour (160 GTA colours), paint finish (classic, metallic, pearl, matte, metal, chrome), livery (mod), classic livery |
| Body | Spoiler, front and rear bumper, side skirts, exhaust, frame / roll cage, grille, hood, left and right fender, roof, arch covers, aerials, exterior trim, fuel tank, windows, plate holder, vanity plate |
| Wheels | Rims per wheel type (sport, muscle, lowrider, SUV, offroad, tuner, high end, Benny's original, Benny's bespoke, open wheel, street, track, bike), rear rims (bikes), custom tyres, tyre smoke on/off and RGB colour |
| Interior | Trim, ornaments, dashboard, dials, door speakers, seats, steering wheel, shifter, plaques, speakers, trunk |
| Lights | Xenon on/off, xenon colour (14 colours), neon layout (front, back, sides, combinations), neon RGB colour |
| Other | Horn (with names), window tint (7 tints), plate style (6 styles), engine block, air filter, struts, hydraulics |

Prices use a base price plus `priceStep × variant` for mod lists. Removing a mod-list, wheel, livery, neon-layout or window-tint option (back to stock) costs `RemoveFactor` (25 %) of the base price. Materials are consumed per installed change, but not when returning to stock or turning an option off:
- paint_can for colours, with a spray_gun required,
- vinyl for liveries,
- bodykit_parts for the body kit (2 for frame and hydraulics),
- rims, tyre_smoke_kit, interior_parts, xenon_kit, neon_kit, window_tint, horn and plate_kit for their categories.

Dependent options are resolved automatically: the xenon colour needs xenon, the neon colour needs neon, and the tyre smoke colour needs tyre smoke. Blocked classes are cycles, boats, helicopters, planes and trains.

### 4.12 Supplier, ordering & supply runs

- **Computer → Supplier** (perm `order`) opens the supplier NUI with these parts:
  - the catalogue by category with search,
  - daily limits per workshop ("x / y left", "Sold out"),
  - items restricted to a minimum grade (`minGrade`), which lower grades don't see,
  - a cart,
  - a delivery-mode choice with the price multiplier,
  - the current balance and the balance after the order,
  - an **Orders** tab with the last 20 orders and their status.
- The payer is `payFrom = "society"` (workshop account, default) or `"player"` (bank or cash).

| Mode | Price | Delivery |
|---|---|---|
| Instant | 100 % | Straight into the workshop storage |
| Delayed | 85 % | Into the storage after 15 min. Survives restarts, and items that don't fit wait for the next delivery |
| Supply run | 65 % | Mechanics pick the goods up with a van |

- Each workshop boss can enable or disable modes in **Workshop settings → Supply**.
- **Supply run** (perm `supply_run`, requires the workshop `garage` and `supply` points):
  - Start the run at the computer. The oldest orders awaiting pickup that fit into the van (10 items per crate, max 12 crates) are taken.
  - A `burrito3` van with a `SUPP####` plate spawns at the garage point with fuel and keys. A route leads to one of three pickup locations (port, Elysian Island, container terminal), where a crate pile stands.
  - Each crate is carried by hand from the pile into the rear of the van (rear doors open, 4 s per crate). At the workshop, crates are carried from the van to the supply point (3.5 s per crate), where they stack up visually.
  - The run must be finished within 30 min. Otherwise, or if the van is lost, the orders return to "awaiting pickup". A finished van is returned 20 s later.
  - **Theft:** anyone can take crates out of an **unlocked** supply van (3 s each). The crate becomes the item **Parts Delivery** (`mech_supply_crate`), and only the workshop that ordered it can hand it over at its supply point with **Deliver crates**.
- Every order and run is logged. The orders log is visible in **Workshop settings → Orders**.

### 4.13 Crafting

- **Workbench → Crafting** (perm `craft`, on duty, at the workbench) opens an ox_lib menu grouped into kits, parts, body, tools, props and recycling. It shows ingredients, tools and "have / need", and asks for the batch amount (1–10).
- Each piece plays a **bench scene** (sorting, welding, drilling, hammering, grinding with sparks, pouring). The product appears on the bench and the mechanic takes it. The server accepts a craft after 85 % of its duration.
- Materials come from salvage of replaced parts and from mission rewards: scrap metal, aluminium, rubber, plastic, electronics and used oil. Used oil can be recycled into engine oil.
- A product crafted from stolen items stays stolen, with its quality and origin (a workbench can't launder parts).
- `OpenServer.OpenCustomCrafting` lets you use your own crafting system instead.

**Recipes (26):**

| Result | Ingredients | Tools | Time |
|---|---|---|---|
| Repair Kit | 3 scrap metal, 2 rubber, 2 plastic, 1 electronics | toolbox | 15 s |
| Emergency Patch Kit | 2 rubber, 1 plastic, 1 scrap metal | – | 10 s |
| Cleaning Kit | 2 plastic, 1 rubber | – | 6 s |
| Advanced Repair Kit | 1 repair kit, 2 electronics, 2 aluminium, 3 scrap metal | toolbox, impact wrench | 30 s |
| Brake Pads | 2 scrap metal, 1 rubber | toolbox | 12 s |
| Brake Discs | 4 scrap metal | toolbox, impact wrench | 18 s |
| Spark Plugs | 1 scrap metal, 1 electronics | toolbox | 8 s |
| Timing Belt | 3 rubber | – | 10 s |
| Tyre | 6 rubber, 1 scrap metal | impact wrench | 15 s |
| Shock Absorber | 3 scrap metal, 1 used oil | toolbox, impact wrench | 18 s |
| Radiator | 5 aluminium, 2 plastic | toolbox | 25 s |
| Alternator | 3 electronics, 2 scrap metal, 1 aluminium | toolbox | 25 s |
| Fuel Pump | 2 electronics, 2 plastic, 1 scrap metal | toolbox | 20 s |
| Car Battery | 3 scrap metal, 2 plastic, 1 electronics | toolbox | 20 s |
| Body Panel | 5 scrap metal | toolbox | 20 s |
| Bumper | 6 plastic, 1 scrap metal | toolbox | 18 s |
| Headlight | 3 plastic, 2 electronics | toolbox | 12 s |
| Car Hood | 6 scrap metal, 2 aluminium | toolbox | 25 s |
| Trunk Lid | 5 scrap metal, 1 aluminium | toolbox | 22 s |
| Car Door | 7 scrap metal, 2 plastic, 1 electronics | toolbox | 30 s |
| Slim Jim | 1 scrap metal | toolbox | 6 s |
| Jump Starter | 4 electronics, 2 plastic, 1 scrap metal | toolbox | 25 s |
| Traffic Cone ×2 | 3 plastic | – | 6 s |
| Work Sign | 2 scrap metal, 1 plastic | – | 8 s |
| Road Barrier | 4 scrap metal, 2 plastic | toolbox | 12 s |
| Engine Oil | 4 used oil | toolbox | 20 s |

### 4.14 Billing

- **Creating a bill.** Mechanic menu → **Create bill** (perm `billing`). The NUI **prefills the lines** from the work this mechanic did on the vehicle:
  - repairs: labor × `laborMultiplier` + supplier price of the parts × (1 + `partsMarkup` %),
  - tuning: the final price.

  Lines with the same label and price are merged. The mechanic picks a customer from the nearby players (within 6 m), can add or edit lines (quantity, unit price) and add a note. The window shows his commission.
- **Paying.** The customer gets a bill window: an invoice with lines, subtotal, total and note, with **Pay cash**, **Pay from bank** or **Decline**. Customers can reopen unpaid bills with `/mechbills` or at any **payment terminal** of the workshop.
- **Payout.**
  - The workshop society receives the total minus the commission. The mechanic's commission (workshop setting, default 10 %) is paid to his bank (`commissionPayout`).
  - If the mechanic is offline, the society keeps the whole amount.
  - Illegal workshops accept cash only and the whole amount goes to the mechanic.
- **Limits.** At most 25 lines, $100 000 per line, $500 000 total, a 200-character note, 5 unpaid bills per customer, a 5 s send cooldown. Bills expire after 30 min.
- Bills are bound to character IDs and survive a reconnect. `OpenServer.OnBillPaid(bill)` fires after every payment.
- The bills log is available in **Workshop settings → Bills** (20 per page).

### 4.15 Mechanic menu (F6 / radial)

The menu opens with `F6` (`Config.Keys.mechanicMenu`) or via the ox_lib radial item **Mechanic menu**. It is available only while on duty (or in your own illegal workshop). It works on the closest vehicle within 5 m, and every option is shown only with its permission.

| Action | Permission | Description |
|---|---|---|
| Diagnose / Open last diagnostics | diagnose | OBD diagnostics (4.5) |
| Service book | diagnose | History of the closest vehicle |
| Create bill | billing | Billing (4.14) |
| Missions | missions | NPC missions (4.16) |
| Push vehicle | tow | Walk to the bumper, brace and push: `W` push, `A`/`D` steer, `F` or `X` let go. 1.2 m/s; you let go when the car rolls faster than 5 m/s. Heavy classes are blacklisted. |
| Flip vehicle | tow | 9 s scene: brace, rock, rock hard, roll over |
| Unlock (slim jim) | tow + Slim Jim item | 10 s scene (check, insert, search, hook, pull). 70 % success; on failure 25 % chance the slim jim breaks and the car alarm goes off. On success the door opens and `Config.GiveKeys` runs. Optional police dispatch through `Config.UnlockDispatch`. The Slim Jim item starts the same action. |
| Load / unload flatbed | tow | Winch towing (below) |
| Impound | impound | Photos from the front and rear with a camera flash, then an impound report (12 s). The vehicle is handed to `OpenServer.ImpoundVehicle` (default: deleted). Refused for occupied, attached or mission vehicles. |

**Flatbed towing** (`Config.Flatbeds`, default model `flatbed`). Use the menu or the target **Flatbed** on the truck.

- **Loading on foot:**
  1. Lower the bed at the controls (hydraulic sound).
  2. Hook the winch cable on the vehicle standing behind the truck.
  3. Winch it up. The vehicle slides onto the bed with a visible steel cable.
  4. Strap the wheels.
- **Unloading:** remove the straps and release the bed. The vehicle stands on the ground behind the truck.
- From the driver seat the bed is operated remotely.
- Boats, aircraft, commercial vehicles and trains can't be loaded.

**Jump start** (Jump Starter item, **anyone**) on a vehicle with a critical or failed battery:
1. Carry the booster to the hood and open it.
2. Connect the red and black clamps (sparks, visible jumper cables).
3. Charge, then make a weak crank attempt.
4. The engine starts. Disconnect.

The battery is set to 20 %.

### 4.16 NPC missions

Choose **Missions** in the mechanic menu (perm `missions`). The rules:
- one mission at a time,
- a 120 s cooldown per character,
- a 30 min time limit,
- the mission is cancelled when you go off duty.

The customer vehicle spawns server-side when you get within 180 m and is moved to the nearest roadside. A blip and route show the way. In 75 % of missions the **owner waits** next to the car: he waves when you arrive, watches you work, stands impatiently, and afterwards walks over, pays you in cash with an animation and gives a thumbs up. Money is paid as cash. **`societyShare` (20 %)** of the money reward is added **on top** to the workshop society.

| Mission | Task | Needs | Reward |
|---|---|---|---|
| Towing | A broken-down car (engine health 100, engine 5 %). Tow it to the workshop: its first bay, else lift, else garage point. Without those points, the closest configured drop-off. Unload it within 15 m. | Flatbed | $700–1 200 |
| Dead battery | Jump start the car | Jump Starter | $350–600 |
| Flat tyre | Scene: tyre and jack next to the wheel, jack up, loosen with the impact wrench, remove, mount, tighten, lower (18 s). The tyre quick repair also works. | 1 Tyre (consumed), Car Jack | $400–700, 50 % chance of 1 rubber |
| Out of fuel | Put the jerry can down at the filler, open the cap, pour, close (12 s). Fuel is set to 35. | – | $250–450 |
| Scrapping a wreck | No owner. 3 steps around an abandoned wreck (36 s total): cut off the hood, unbolt wheels, grind the trunk, cut a door. Each part comes off and is carried to the scrap pile. | Toolbox | $150–300 + 3–6 scrap metal, aluminium, rubber, plastic, electronics (by chance) |

Locations: 23 city and 14 county roadside spots. Customer cars are picked from 28 common models, and wrecks from 7 models.

### 4.17 Placeable props

The items Traffic Cone, Road Barrier, Work Sign and Toolbox are used from the inventory:
- A ghost preview follows the camera, green when placeable and red when too far (6 m). `E` places, scroll or `←` `→` rotate, `Backspace` cancels.
- The player **carries** the item to the spot and puts it down with an animation. The server then creates a networked, frozen prop.
- Each character can place up to **20** props. **Anyone** can pick a prop up again (target **Pick up**) and receives the item.
- Props are removed on resource stop, and props left over after a crash are adopted again.

### 4.18 Workshop account, deposit & service vehicles

- **Deposit.** At the **computer**, every employee of the workshop (job) and every admin can deposit **cash or bank** money (max $1 000 000 per deposit) into the workshop account: the society of the first job. The current balance is shown. Withdrawals are done in your boss menu.
- **Service vehicles.** The **Service vehicles** point (perm `duty`, on duty) spawns one vehicle per mechanic from `Config.ServiceVehicles` (Flatbed, Tow truck, Supply van). It gets a `MECH###` plate, full fuel (`Config.SetFuel`) and keys (`Config.GiveKeys`). Return it in the same menu. It is deleted when the player disconnects or the resource stops.

### 4.19 Stolen parts, quality & origin

Stolen parts are normal part items with metadata `{ stolen = true, quality = 5–100, origin = "<vehicle>" }`, created by the illegal DLC. Inventories without metadata support treat every part as clean.

| Rule | Legal workshop | Illegal workshop |
|---|---|---|
| Parts used | **Clean parts only** (`Config.StolenParts.legalAccepts = false`); stolen parts are refused | Stolen parts first (lowest quality first), then clean ones |
| Installed stolen part | – | Part condition = item quality; part origin = `unknown` |
| Wear of `unknown` parts | ×1.5 (`wearMultiplier`) | ×1.5 |
| Diagnostics | Shows the **unknown origin** badge | – |

- Tools may have any metadata. Crates of a DLC courier mission are never counted or consumed.
- Quick take from the storage follows the same rules.
- A repair station replaces parts with clean ones and clears the origin.

### 4.20 Illegal DLC integration (overview)

`pls_mechanic_illegal` (`Config.IllegalResource`) is a paid DLC that adds **crew workshops** on top of this base resource. See its own documentation: **pls_mechanic_illegal** (documentation comes with the DLC). The base provides the following integration:

- **Creating.** `/mechanicadmin` → **Create illegal workshop** is offered only while the DLC runs. Enter a name and an owner (server ID of an online player, changeable later with **Set owner**). An existing workshop can switch its type.
- **Illegal workshop.**
  - No jobs, duty, blip, society account or workshop settings: the DLC crew decides access.
  - Allowed points: bay, car lift, storage, workbench, payment terminal, plus the DLC points.
  - A crew member standing within `Config.IllegalShopRadius` (40 m) of any point works for the crew there without duty. Repair, diagnostics, fetching, lifts, tuning, crafting, billing and the mechanic menu all work.
- **Privacy.**
  - Illegal workshops are never in GlobalState and are sent only to crew members (and to admins for the creator).
  - Lift positions of illegal workshops are kept only in the vehicle statebag.
  - Illegal storage IDs carry a random key and open only for players with the `storage` permission standing at a storage point.
- **Billing and history.** Bills are cash only, paid straight to the mechanic. Illegal work is not written to the service book. Crew members can read a service book only with the vehicle next to them.
- **Exports** used by the DLC: see section 9.

### 4.21 Animations system

All work is played by the built-in `Anim` library through data-driven scenes in `configs/animations.lua`, `configs/extras.lua`, `configs/crafting.lua`, `configs/missions.lua` and `configs/tuning.lua`:
- **Anims.** 20+ presets: hood work, side work, lying under the car with enter and exit transitions, standing overhead, kneeling, crouching, pouring, cleaning, tablet, button press, welding, hammering, box carry, put down and pick up.
- **Props.** Hand tools (screwdriver, torque wrench, grinder, flashlight, rag, sponge, coolant can, jack) and carried parts (part box, wheel, radiator, engine part, gearbox, brake caliper, EV module, EV motor, door, bonnet, bumpers, body panel, glass). Old parts are left on the ground and collected; a drain pan is placed under the car.
- **Sounds.** Impact wrench bursts, grinder, scanner beeps, device connected, button.
- **Particles.** Oil drain, fluid drain, coolant steam, battery sparks, grinder sparks, wash water.
- **Repair scenes.** 44 scenes keyed as `service:<part>`, `core:<part>`, `body:<kind>`, `kit:<kit>` and `default:<access>`. They are built from the actions `open`, `walk`, `phase`, `remove`, `fetch`, `place` and `collect`, plus `after` phases such as the engine test run.
- **Networking.** Props and particles are networked (other players see them) and props on the ground have no collision by default.
- Every anim dict, model, particle and sound in the configs exists in the base game, and every key can be swapped for your own assets.

### 4.22 Admin commands

| Command | Access | Description |
|---|---|---|
| `/mechanicadmin` | `Config.AdminGroup` (`group.admin`) | Workshop creator (`Config.AdminCommand`) |
| `/mechanicadminfix` | `group.admin` | Fully repairs the vehicle you sit in, or the closest one within 6 m: all mechanic parts to 100 % plus native damage. Mileage and ownership stay. |
| `/mechsociety [job]` | `group.admin` | Prints society-account diagnostics to the server console (framework, esx_addonaccount / esx_society state, shared accounts, `HasSocietyAccount`) |

---

## 5. UI (NUI views)

The NUI is a React app with its own mechanic design, available in English and Czech.

| View | Opened by | Shows |
|---|---|---|
| **Diagnostics** | OBD scan / reopen | Vehicle header (plate, model, class, mileage, EV) and health gauges (engine, body, fuel tank). Tabs Service parts / Core parts / Bodywork / Fault codes / Tuning with state bars, next service, item and tool requirements (have/need), location hints and origin badges. Selection tools and **Start repair**. |
| **Workflow** (overlay) | Repair, quick repair, kit, tuning installation | Title (repair or tuning installation), step list with statuses, current phase and progress, waiting-for-parts panel (have / need / in storage, route hint), cancel hint, final result |
| **Tuning** | Bay target | Groups Performance, Body, Wheels, Paint, Interior, Lights, Other. Option lists with prices, colour palettes and RGB pickers, installed/stock markers, "missing materials or tools", the Changes cart with total, revert, camera controls (rotate, zoom, reset), keyboard navigation, draft-restored notice |
| **Supplier** | Computer | Catalogue (categories, search, daily limits, sold out), cart, delivery modes with multipliers, balance before and after, Orders tab |
| **Settings** | Computer (`manage_shop`) or creator | Tabs **Permissions** (jobs × grades matrix), **Prices** (labor multiplier, parts markup, tuning markup, commission with live examples), **Supply** (enable modes), **Bills** log, **Orders** log. Unsaved-changes guard. |
| **Service book** (history) | Service Book item / menu | Plate, model, mileage, record count, last visit, type filter, timeline of records with parts |
| **Create bill** | Mechanic menu | Nearby customers, prefilled lines, add/edit lines, note, totals, commission |
| **Bill** | Customer | Invoice with lines, subtotal, total, note, pay cash / bank, decline, paid/declined stamps |
| **Tuning catalog** | Customer (target on a vehicle in a tuning bay) | Tuning menu in customer mode: live preview, prices, pending order banner, send / cancel order |
| **Quote** | Customer | Items of the mechanic's cart with Ordered / Extra tags, extra total, total, countdown, accept / decline |

### Building the UI from source

The resource ships with the built UI in `web/dist`, so nothing has to be built to run it. The full source is in `web/`: React 18, TypeScript, Vite and Mantine.

```bash
cd web
npm install        # once, needs Node.js 18+
npm run dev        # browser preview with mock data (DEV panel in the corner, ?lang=cs for Czech)
npm run build      # type check + build into web/dist, then restart the resource
```

| Folder | Content |
|---|---|
| `web/src/views` | One file per NUI view (Diagnostics, Workflow, Tuning, Quote, Bill, BillCreate, Supplier, History, Settings) |
| `web/src/components` | Shared parts: window frame, controls, items, vehicle header, orders |
| `web/src/lib` | NUI bridge (`fetchNui`), translations and formatting, toasts, workflow state |
| `web/src/dev` | Mock data and the DEV panel, only loaded in the browser preview |
| `web/src/styles`, `web/src/theme.ts` | Design tokens, fonts and the global style |

UI texts come from `locales/*.json` (keys starting with `ui_`). Translate them there, not in the source.

---

## 6. Configuration reference

### 6.1 `config.lua` – general

| Key | Default | Meaning |
|---|---|---|
| `Config.Debug` | `false` | Debug prints (including plate-spoof attempts) |
| `Config.Currency` | `"$"` | Currency symbol |
| `Config.AdminCommand` | `"mechanicadmin"` | Creator command |
| `Config.AdminGroup` | `"group.admin"` | Ace group for the admin commands |
| `Config.RequireDuty` | `true` | Job actions require duty in the workshop |
| `Config.DiagnosticsReopen` | `10` | Minutes a report can be reopened without a new scan (0 = off) |
| `Config.ImagePath` | `"nui://ox_inventory/web/images/%s.png"` | Item images for the NUI |
| `Config.IllegalResource` | `"pls_mechanic_illegal"` | Name of the illegal DLC resource |
| `Config.IllegalShopRadius` | `40.0` | m – crew member is "in" his illegal workshop within this distance of any point |

**`Config.Deposit`**

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Deposit to the workshop account at the computer |
| `max` | `1000000` | Max amount of one deposit |
| `methods` | `{ "cash", "bank" }` | Payment methods |

**`Config.Keys`**

| Key | Default | Meaning |
|---|---|---|
| `mechanicMenu` | `"F6"` | Mechanic menu (on duty) |
| `cancel` | `"X"` | Cancel running repair, tuning installation, scene or placement |

**`Config.Stash`**: `slots = 80`, `weight = 1000000`. These are the default slots and weight of every workshop storage.

**`Config.Fetch`**

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Parts fetching on (false = all parts and tools in the inventory before the start) |
| `requireStock` | `true` | Refuse the start when a part or tool is in neither the inventory nor the storage |
| `timeout` | `10` | min, waiting for parts is cancelled after this time (0 = no limit) |
| `maxDistance` | `120.0` | m, waiting is cancelled beyond this distance from the vehicle |
| `resumeDistance` | `4.0` | m, "Continue" target distance |
| `quickTake` | `true` | Storage action "Take parts for the job" |
| `carry` | `"part_box"` | Prop carried after a quick take (`false` = none) |
| `storageBlip` | `true` | Route blip to the storage while waiting |

**`Config.DefaultBlip`**: `enabled = true`, `sprite = 446`, `color = 5`, `scale = 0.8`.

**`Config.DefaultShopSettings`** (the boss changes these in game)

| Key | Default | Allowed range | Meaning |
|---|---|---|---|
| `laborMultiplier` | `1.0` | 0.1–5.0 | Multiplier of labor prices on bills |
| `partsMarkup` | `20` | 0–300 % | Added to the supplier price of used parts on bills |
| `tuningMarkup` | `0` | 0–300 % | Added to tuning prices |
| `commission` | `10` | 0–100 % | Share of every paid bill for the mechanic |
| `supplyModes` | `{ instant = true, delayed = true, run = true }` | – | Delivery modes enabled for the workshop |

**`Config.PermissionList`**: order of the permissions in the settings UI (see 4.2). **`Config.DefaultPermissions`**: default matrix by grade (see 4.2).

**`Config.PointTypes`**: point types (see 4.1). Keys: `label`, `icon`, `radius`, `multiple`, `kinds`, `fields` (types `number`, `checkbox`, `select`, `text`, `multi-select`).

**`Config.ServiceVehicles`**: `{ model = "flatbed", label = "Flatbed" }`, `{ model = "towtruck", label = "Tow truck" }`, `{ model = "burrito3", label = "Supply van" }`.

**`Config.Items`**: script key → inventory item name (86 items, see section 7). Rename items here only.

**`Config.UsableItems`**: `tyre, car_battery, car_wheel, obd_scanner, toolbox, car_jack, jump_starter, slim_jim, service_book, repair_kit, advanced_repair_kit, patch_kit, cleaning_kit, traffic_cone, road_barrier, work_sign`.

**`Config.Props`**: hand props with `model`, `bone`, `pos` and `rot`:

| Key | Default model |
|---|---|
| `scanner` | `prop_cs_tablet` |
| `toolbox` | `prop_tool_box_04` |
| `wrench` | `prop_tool_wrench` |
| `impact_wrench` | `prop_tool_drill` |
| `battery` | `prop_car_battery_01` |
| `tyre` | `prop_wheel_tyre` |
| `oil` | `prop_oilcan_01a` |
| `spray_gun` | `prop_paint_spray01a` |
| `laptop` | `prop_laptop_01a` |
| `crate` | `prop_cs_cardbox_01` |
| `car_jack` | `prop_carjack` |
| `engine_part` | not set by default |
| `lift` | not set by default; without a model only the vehicle is lifted |

### 6.2 `configs/client.lua` – client hooks

| Key | Default | Meaning |
|---|---|---|
| `Config.OpenBossMenu(shopId, job)` | `exports['pls_bossmenu']:OpenBossMenu(job)` | Boss-menu point |
| `Config.SetFuel(vehicle, fuel)` | statebag `fuel` + native + LegacyFuel / ox_fuel | Fuel for missions, service vehicles, supply van, EV drain |
| `Config.GiveKeys(vehicle, plate)` | empty | Keys for service vehicles, supply van, unlocked vehicles |
| `Config.UnlockDispatch(vehicle, coords)` | `nil` (off) | Police dispatch after a slim-jim unlock |
| `Config.ShowMileage` | `true` | Odometer above the minimap while driving |
| `Config.MileageUnit` | `"km"` | `"km"` / `"mi"` |

### 6.3 `configs/parts.lua` – vehicle model

| Key | Default | Meaning |
|---|---|---|
| `Config.PartStates` | `optimal = 70, worn = 40, critical = 15` | State thresholds (%) |
| `Config.ExcludedClasses` | 13, 14, 15, 16, 21 | Classes without a parts system |
| `Config.ClassWear` | 0.8–1.6 per class | Wear multiplier (compacts 1.0, SUVs 1.1, muscle 1.2, sports 1.3, super 1.5, open wheel 1.6, industrial/utility/commercial 0.8…) |
| `Config.TuningWear` | engine +0.15/level, transmission +0.15/level, brakes −0.1/level, turbo +0.25 | Extra wear from performance tuning |
| `Config.StolenParts` | `legalAccepts = false`, `wearMultiplier = 1.5` | Stolen-part rules |
| `Config.ElectricVehicles` | 20 models | EV detection |
| `Config.ServiceParts` | 11 parts | See 4.4 (keys: `label`, `type`, `interval`, `items`, `tools`, `damages`, `snap`, `salvage`, `location`, `access`, `duration`, `labor`, `perm`, `obd`) |
| `Config.CoreParts` | 13 parts | See 4.4 (keys as above plus `requiresTurbo`) |
| `Config.OBDCodes` | 18 codes | Code descriptions |
| `Config.CollisionDamage` | `minSeverity = 8`, `multiplier = 1.0`, zones, `heavySeverity = 60`, `heavy` | Collision model |
| `Config.BodyParts` | 10 body kinds | See 4.4 |
| `Config.BodyRepairPermission` | `"repair_body"` | Permission for bodywork |
| `Config.RepairKits` | 4 kits | See 4.8 (`mechanicOnly`, `jobs`, `duration`, `engineHealth`, `bodyHealth`, `corePartsMin`, `failedToCritical`) |
| `Config.QuickRepairs` | `tyre`, `car_wheel` (`requireJack = true`), `car_battery` | Quick repairs |

**`Config.Mileage`**

| Key | Default | Meaning |
|---|---|---|
| `syncInterval` | `60` | s, the driver reports mileage at least this often |
| `syncDistance` | `1.0` | km, report sooner when reached |
| `maxSpeed` | `450` | km/h, server anti-cheat for mileage |
| `saveInterval` | `5` | min, batch save of owned vehicles |
| `npcMileage` | `{ min = 20000, max = 250000 }` | Mileage of not-owned vehicles |
| `npcWear` | `{ min = 10, max = 90 }` | Service-part wear % of not-owned vehicles |
| `npcCoreWear` | `{ min = 0, max = 35 }` | Core-part damage % of not-owned vehicles |
| `npcMinCore` | `45` | Core parts of not-owned vehicles never start below this % |
| `npcMinService` | `15` | Service parts never start below this % |
| `newVehicleWindow` | `300` | s, owned within this time after the first drive = purchase |
| `newVehicleMaxKm` | `5.0` | km driven limit for purchase detection |
| `newOwnedMileage` | `{ min = 5, max = 60 }` | Mileage of brand-new vehicles |
| `npcCacheHours` | `6` | Not-owned vehicles are forgotten after this idle time |

### 6.4 `configs/effects.lua` – driving effects

| Key | Default | Meaning |
|---|---|---|
| `Config.Effects.Enabled` | `true` | Effects on/off (parts still wear) |
| `Notify.onEnter` | `true` | Dashboard warnings on entering |
| `Notify.enterCore` / `enterService` | `"critical"` / `"failed"` | State reported on enter |
| `Notify.changeCore` / `changeService` | `"worn"` / `"critical"` | State reported when a part gets worse while driving |
| `Intervals` | `stall = 5000, stutter = 400, lights = 120, burst = 10000, turbo = 2000` | ms between random effect rolls |
| `Collision` | `window = 200, cooldown = 750` | ms – impact measurement and cooldown |
| `Steering` | `minSpeed = 25.0, wobbleFrequency = 1.3` | Pull and wobble settings |
| `Temperature` | `enabled = true, ambient = 20, normal = 90, max = 140, heatIdle = 0.5, heatLoad = 3.0, coolBase = 2.2, coolAirflow = 1.8, coolOff = 0.015, warn = 110, overheat = 120, overheatPower = 0.55, shutdown = 130, restart = 105, engineDamagePerMinute = 2.0` | Engine temperature simulation (°C, °C/s) |
| `Particles` | `networked = true`, `smoke` (`ent_amb_generator_smoke`), `steam` (`ent_amb_steam_vent_open_lgt`) | Engine-bay particles |
| `Wear` | `coreAging`, `radiatorEngine`, `alternatorBattery` | Extra wear per km (see 4.4) |
| `Parts` | per part: `worn` / `critical` / `failed` / `empty` | Effects: `power`, `topSpeed`, `brake`, `grip`, `shift`, `pull`, `wobble`, `cooling`, `stall`, `stutter`, `slip`, `crank`, `noStart`, `noDrive`, `lights`, `smoke`, `burst`, `evDrain` |

### 6.5 `configs/tuning.lua` – tuning

| Key | Default | Meaning |
|---|---|---|
| `MaxDistance` | `8.0` | m, the mechanic must stay this close to the vehicle |
| `RemoveFactor` | `0.25` | Returning a visual part to stock costs base price × factor |
| `Cooldown` | `1500` | ms between two confirmations |
| `MaxChanges` | `60` | Max changes per confirmation |
| `DraftMinutes` | `15` | Unconfirmed cart restored within this time (0 = off) |
| `MaxModIndex` | `300` | Highest accepted mod index (addon vehicles) |
| `SaveOwnedVehicles` | `true` | Save properties of owned vehicles to the garage table |
| `SessionTimeout` | `30` | min, a tuning or catalog session without a heartbeat is closed (the preview is always reverted) |
| `HidePlayer` | `true` | Hide your own ped for the tuning camera |
| `CameraSpeed` | `5.0` | Camera smoothing |
| `BlockedClasses` | 13, 14, 15, 16, 21 | Classes that can't be tuned |
| `Animations` | `idle`, `work`, `paint`, `laptop`, `hood`, `under`, `wheel` | Mechanic poses in the menu |
| `WorkTime` | `perChange = 2000, max = 12000` | Instant install time (only when `Install.enabled = false`) |
| `Cameras` | `default`, `front`, `hood`, `rear`, `trunk`, `side`, `side_right`, `wheel`, `wheel_rear`, `interior`, `top`, `under` | Camera presets (`target`, `bone`, `angle`, `distance`, `height`, `fov`, `door`) |
| `Performance` | 6 categories | See 4.11 (`key`, `mod`, `prop`, `cam`, `tool`, `returnItemOnRemove`, `removePrice`, `levels`, `requires`, `toggle`, `iceOnly`, `item`, `price`) |
| `Visual` | 53 categories | See 4.11 (`key`, `type`, `mod`, `prop`, `group`, `price`, `priceStep`, `material`, `tool`, `needs`, `palette`, `target`, `cam`) |
| `WheelTypes` / `PaintTypes` / `WindowTints` / `PlateStyles` / `NeonLayouts` / `XenonColors` / `HornNames` / `Colors` | lists | Options offered in the NUI (remove lines you don't want) |

**`Config.Tuning.Catalog`** (customer catalog, see 4.11)

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Target **Tuning catalog** on vehicles in tuning bays |
| `performance` | `true` | Customers also see performance parts |
| `requireMechanic` | `true` | Catalog only while a mechanic of the workshop is available |
| `illegal` | `false` | Catalog in illegal workshops (DLC) too |
| `maxDistance` | `6.0` | m, the customer has to stay this close to the vehicle |
| `orderMinutes` | `120` | min, an order waits for a mechanic this long |
| `approval` | `true` | Changes outside the order need the customer's approval (quote) |
| `approvalDistance` | `30.0` | m, the customer has to be this close to approve |
| `approvalTimeout` | `60` | s, a quote without an answer counts as declined |

**`Config.Tuning.Install`** (step-by-step installation)

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Animated installation (false = instant confirmation) |
| `carry` | `true` | Carry the part or crate to the vehicle |
| `calibration` | `6000` | ms laptop calibration after engine, transmission and turbo |
| `calibrationTool` | `"tuning_laptop"` | Categories with this tool get the calibration |
| `durations` | `performance = 12000, body = 9000, wheels = 8000, paint = 10000, interior = 7000, lights = 6000, other = 6000, settings = 4000` | ms of work per change by group |
| `removalFactor` | `0.6` | Removing takes 60 % of the time |
| `unbox` | `2000` | ms unpacking the crate |
| `test` | `2500` | ms test after installation |
| `resultTime` | `4000` | ms result shown in the overlay |
| `serverCheck` | `0.9` | Server accepts a step after this share of its work time |
| `leftovers` | `true` | Removed parts lie on the ground until the end |
| `maxDistance` | `14.0` | m, the installation is cancelled beyond this distance |
| `spotGap` | `0.65` | m, distance of work spots from the body |
| `groupOrder` | `performance, body, wheels, interior, lights, other, paint` | Installation order (dependencies resolved automatically) |
| `Anims`, `Props`, `Sounds`, `Particles`, `PropSounds`, `RemovalPhases`, `CalibrationPhases`, `Tests` | presets | Scene building blocks |
| `Scenes` | 42 scenes (engine, turbo, transmission, brakes, suspension, armor, bumpers, spoiler, exhaust, roof, windows, rims, tyres, hydraulics, paint, livery, interior, seats, xenon, neon, horn, window tint, plate, engine bay, generic…) | Installation scenes (`take`, `part`, `work`, `removal`, `test`) |
| `CategoryScenes` | category → scene | Categories without an entry use `generic` |

### 6.6 `configs/supplier.lua` – supplier & billing

**`Config.Supplier`**

| Key | Default | Meaning |
|---|---|---|
| `payFrom` | `"society"` | `"society"` (workshop account) or `"player"` |
| `playerAccount` | `"bank"` | `"bank"` / `"cash"` when `payFrom = "player"` |
| `orderCooldown` | `3` | s between two orders of one player |
| `maxCount` | `999` | Max pieces of one item per order |
| `historySize` | `20` | Last orders shown |
| `modes.instant` | `enabled = true, multiplier = 1.0` | Straight to storage |
| `modes.delayed` | `enabled = true, multiplier = 0.85, minutes = 15` | Delivered later (survives restart) |
| `modes.run` | `enabled = true, multiplier = 0.65` | Supply run |

**`Config.Supplier.run`**

| Key | Default | Meaning |
|---|---|---|
| `vehicle` / `vehicleType` | `"burrito3"` / `"automobile"` | Van model and type |
| `platePrefix` | `"SUPP"` | Plate = prefix + 4 digits |
| `itemsPerCrate` | `10` | Item pieces per crate |
| `maxCrates` | `12` | Van capacity |
| `timeLimit` | `30` | min to finish the run |
| `vanDistance` | `15.0` | m, the van must be parked this close to the pickup or supply point |
| `loadDuration` / `unloadDuration` / `takeDuration` | `4000` / `3500` / `3000` | ms per crate |
| `vanDespawn` | `20` | s before a finished van is returned |
| `pileProp` | `"prop_boxpile_07d"` | Crate pile at the pickup |
| `crate` | `prop_cs_cardbox_01` (box carry) | Carried crate |
| `vanDoors` | `{ 2, 3, 5 }` | Doors opened while loading |
| `carryDistance` | `2.0` | m to take or put down a crate |
| `stackSize` / `stackTime` | `6` / `60` | Visual crate stack at the supply point |
| `anims` | `lift`, `load` (`anim@heists@load_box`) | Crate animations |
| `blip` | `sprite = 478, color = 5, scale = 0.9` | Pickup blip |
| `locations` | Port of Los Santos – Pier 400, Elysian Island – Pacific Bait, Terminal – Container Yard | Pickup locations |

**`Config.Supplier.catalog`** (instant price per piece; `limit` = pieces per workshop per day; `minGrade` = minimum job grade)

| Category | Items (price) |
|---|---|
| service | engine_oil 60, oil_filter 25, air_filter 35, fuel_filter 40, spark_plugs 45, coolant 30, brake_fluid 25, transmission_fluid 55, brake_pads 120, tyre 180, timing_belt 220 |
| core | engine_parts 4 500 (limit 15), transmission_parts 3 500 (15), clutch_kit 900, radiator 450, alternator 380, car_battery 220, fuel_pump 320, brake_discs 260, shock_absorber 180, turbocharger 2 800 (10) |
| ev | ev_battery_module 6 000 (20), ev_motor 7 500 (10), ev_coolant 70 |
| body | car_door 450, car_hood 400, car_trunk 350, car_bumper 300, car_glass 250, car_headlight 180, car_wheel 350, body_panel 150 |
| tools | obd_scanner 1 200 (5), toolbox 650 (10), impact_wrench 480 (10), car_jack 350 (10), jump_starter 280 (10), slim_jim 150 (10), tuning_laptop 3 500 (3), spray_gun 450 (5), service_book 20 |
| kits | repair_kit 350, advanced_repair_kit 1 200 (20), patch_kit 180, cleaning_kit 60 |
| props | traffic_cone 25, road_barrier 90, work_sign 60 |
| performance | engine_stage1 5 000, engine_stage2 9 000, engine_stage3 15 000 (5), engine_stage4 25 000 (3, grade 3+), brakes_stage1 2 000, brakes_stage2 4 000, brakes_stage3 7 000 (5), transmission_stage1 3 000, transmission_stage2 6 000, transmission_stage3 10 000 (5), suspension_stage1 1 500, suspension_stage2 3 000, suspension_stage3 5 000, suspension_stage4 8 000 (5), armor_stage1 5 000, armor_stage2 8 500, armor_stage3 12 500 (5), armor_stage4 17 500 (3), armor_stage5 25 000 (2, grade 3+), turbo_kit 12 000 (5) |
| visual | paint_can 150, bodykit_parts 800, rims 1 200, tyre_smoke_kit 450, xenon_kit 600, neon_kit 900, window_tint 200, vinyl 350, interior_parts 700, horn 150, plate_kit 120 |

**`Config.Billing`**

| Key | Default | Meaning |
|---|---|---|
| `command` | `"mechbills"` | Customer command to reopen unpaid bills (empty = off) |
| `distance` | `6.0` | m, customer distance |
| `maxLines` | `25` | Lines per bill |
| `maxLinePrice` | `100000` | Max price per line (per piece) |
| `maxTotal` | `500000` | Max bill total |
| `maxNoteLength` | `200` | Note characters |
| `maxPending` | `5` | Unpaid bills per customer |
| `expireMinutes` | `30` | Unpaid bill expiry (0 = never) |
| `methods` | `{ "cash", "bank" }` | Customer payment methods |
| `commissionPayout` | `"bank"` | How the mechanic receives commission |
| `sendCooldown` | `5` | s between two bills of one mechanic |

### 6.7 `configs/crafting.lua`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | Built-in workbench crafting |
| `maxAmount` | `10` | Max crafts in one batch |
| `scenes` | `kits`, `parts`, `body`, `tools`, `props`, `recycling` | Bench scene per category (phases share the recipe duration) |
| `products` | per category prop | Product shown on the bench |
| `take` | `mp_common givetake1_b`, 1 300 ms | Taking the product |
| `recipes` | 26 recipes | `result`, `count`, `category`, `duration`, `tools`, `ingredients`, optional `scene`, `prop` (see 4.13) |

### 6.8 `configs/missions.lua`

| Key | Default | Meaning |
|---|---|---|
| `enabled` | `true` | NPC missions |
| `cooldown` | `120` | s between two missions of a character |
| `timeout` | `30` | min to finish |
| `spawnDistance` | `180.0` | m, vehicle created when the mechanic gets this close |
| `snapToRoad` / `snapRadius` | `true` / `150.0` | Move the vehicle to the nearest roadside |
| `despawnDelay` | `45` | s before a finished mission vehicle is removed |
| `societyShare` | `20` | % of the money reward paid on top to the workshop society |
| `blip` | `sprite = 225, color = 47, scale = 0.9, route = true` | Mission vehicle blip |
| `dropOffBlip` | `sprite = 357, color = 5, scale = 0.9, route = true` | Tow drop-off blip |
| `npc` | `chance = 75`, 8 models, 4 scenarios, `greetDistance = 15`, `watchDistance = 25`, `waiting`, `greet` / `pay` / `take` / `thanks` anims | Waiting owner |
| `vehicles` | 28 models | Customer vehicles |
| `locations` | `city` (23), `county` (14) | Roadside spots |
| `types.tow` | `engineHealth = 100.0`, `coreDamage = { engine = 5.0 }`, `dropRadius = 15.0`, 5 `dropOffs`, reward $700–1 200 | Towing |
| `types.jumpstart` | reward $350–600 | Dead battery |
| `types.tyre` | `items = 1 tyre`, `tools = car_jack`, `duration = 18000`, `jackLift = 0.12`, phases, reward $400–700 + rubber 50 % | Flat tyre |
| `types.refuel` | `fuel = 35.0`, `duration = 12000`, jerry-can prop, phases, reward $250–450 | Out of fuel |
| `types.scrap` | `npc = false`, 7 wreck models, `duration = 36000`, `steps = 3`, `tools = toolbox`, `pile` offset, 5 spots, reward $150–300 + materials | Scrapping |

Every type has `enabled`, `icon` and `areas`.

### 6.9 `configs/extras.lua`

**`Config.MechanicMenu`**: `radial = true`, `keybind = true`, `vehicleDistance = 5.0`, `actions = { diagnose, bill, missions, push, flip, unlock, impound, tow, servicebook }` (all `true`).

| Table | Keys & defaults |
|---|---|
| `Config.Push` | `speed = 1.2`, `maxSpeed = 5.0`, `gap = 0.35`, `height = 1.0`, `anim`, `brace` (900 ms), `blacklistClasses` 10, 14, 15, 16, 19, 20, 21 |
| `Config.Flip` | `duration = 9000`, `rockAngle = 7.0`, `rollLift = 0.35`, 4 phases |
| `Config.Unlock` | `duration = 10000`, `successChance = 70`, `breakChance = 25`, `alarm = true`, `giveKeys = true`, `openDoor = true`, `successSound`, `breakSound`, 5 phases |
| `Config.Impound` | `duration = 12000`, phases: front photo, rear photo, report |
| `Config.Towing` | `maxDistance = 12.0`, `cable = true`, phases `lower` 2.5 s, `hook` 3 s, `winch` 5.5 s, `strap` 2.5 s, `unstrap` 2.5 s, `release` 5.5 s; `blacklistClasses` 14, 15, 16, 20, 21 |
| `Config.Flatbeds` | `flatbed = { bone = "bodyshell", offset, rotation, search = vec3(0, -9, 0), radius = 4.5, detach, controls, winch }` – add your own flatbed models |
| `Config.Placeables` | `maxPerPlayer = 20`, `placeDistance = 6.0`, `pickupDistance = 3.0`, `rotateStep = 5.0`, `placeDuration = 1300`, `pickupDuration = 1200`, items `traffic_cone` (`prop_roadcone02a`), `road_barrier` (`prop_barrier_work05`), `work_sign` (`prop_snow_sign_road_06g`), `toolbox` (`prop_tool_box_04`) |
| `Config.JumpStart` | `duration = 15000`, `batteryValue` = critical + 5 (20), `booster` prop, `cables = true`, `startEngine = true`, `sparks`, 4 phases + `start` / `disconnect` |
| `Config.Stations` | `paymentMethods = { "cash", "bank" }`, `societyPayment = true`, `drivePrompt = true`, `promptKey = 38` (E), `camera = true`, `cameraDistance = 2.8`, `cameraHeight = 1.3`, `cameraSpeed = 9.0`, 4 phases |

### 6.10 `configs/animations.lua`

**`Config.Animations.Settings`**

| Key | Default | Meaning |
|---|---|---|
| `progressPosition` | `"bottom"` | ox_lib progress position |
| `walkSpeed` | `1.0` | 1.0 walk, 2.0 jog |
| `walkTimeout` | `8000` | ms max walk to a spot |
| `reachDistance` | `1.2` | m, spot reached |
| `networkProps` | `true` | Props visible to other players |
| `networkParticles` | `true` | Particles visible to other players |
| `groundCollision` | `false` | Props on the ground have collision |
| `toolbox` / `toolboxNeedsItem` | `true` / `true` | Toolbox next to the vehicle during the workflow (only with the item) |
| `engineTest` | `true` | Engine test run after relevant repairs |
| `lie` | `distance = 0.35, heading = 180.0` | Lying under the vehicle |
| `overheadHeight` | `1.6` | Vehicle higher on a lift → standing overhead poses |

The remaining tables are `Config.Animations.Anims`, `Overhead`, `Props`, `Sounds`, `Particles` and `Scenes` (44 repair scenes). See 4.21.

### 6.11 `BRIDGE/config.lua`

| Key | Default | Meaning |
|---|---|---|
| `BRIDGE.Framework` | `"ESX"` (auto-detected) | `ESX` / `QB` / `OX` |
| `BRIDGE.Inventory` | `"ox_inventory"` | `ox_inventory`, `qb_inventory`, `quasar_inventory`, `codem`, `core` |
| `BRIDGE.ESXOld` | `false` | Old ESX versions |
| `BRIDGE.Target` | `"ox_target"` | `ox_target` / `qb_target` |
| `BRIDGE.UseMarkers` | `false` | Markers instead of target |
| `BRIDGE.AllowModelTargetToKeypress` | `false` | Model targets as markers (needs `UseMarkers`) |
| `BRIDGE.UseDrawText` / `BRIDGE.DrawText` | `false` / `"[ E ]"` | 3D text for marker mode |
| `BRIDGE.VehicleInteractKey` | `"G"` | Vehicle interaction menu in marker mode |
| `BRIDGE.QBStashesReplaceByPLS` | `true` | PLS stashes replace qb-inventory stashes |
| `BRIDGE.Notify` | `lib.notify` | Notification function (server and client) |

---

## 7. Items

86 items. Weights are ox_inventory units (grams). **Usable** items are used directly from the inventory. The script removes them itself (`consume = 0`).

| Key | Item name | Label | Weight | Usable | Used for |
|---|---|---|---|---|---|
| `engine_oil` | `mech_engine_oil` | Engine Oil | 4500 | No | Oil service (with oil filter); craftable from used oil |
| `oil_filter` | `mech_oil_filter` | Oil Filter | 400 | No | Oil service |
| `air_filter` | `mech_air_filter` | Air Filter | 500 | No | Air filter service |
| `fuel_filter` | `mech_fuel_filter` | Fuel Filter | 400 | No | Fuel filter service |
| `spark_plugs` | `mech_spark_plugs` | Spark Plugs | 300 | No | Spark plug service; craftable |
| `coolant` | `mech_coolant` | Coolant | 2000 | No | Coolant service |
| `brake_fluid` | `mech_brake_fluid` | Brake Fluid | 1000 | No | Brake fluid service |
| `transmission_fluid` | `mech_transmission_fluid` | Transmission Fluid | 2000 | No | Transmission fluid service |
| `brake_pads` | `mech_brake_pads` | Brake Pads | 1500 | No | Brake pad service (2 per job); craftable |
| `tyre` | `mech_tyre` | Tyre | 9000 | Yes | Tyre service (4), burst tyre repair, quick tyre change, flat-tyre mission; craftable |
| `timing_belt` | `mech_timing_belt` | Timing Belt | 800 | No | Timing belt service; craftable |
| `engine_parts` | `mech_engine_parts` | Engine Rebuild Kit | 25000 | No | Engine repair |
| `transmission_parts` | `mech_transmission_parts` | Transmission Rebuild Kit | 18000 | No | Transmission repair |
| `clutch_kit` | `mech_clutch_kit` | Clutch Kit | 7000 | No | Clutch repair |
| `radiator` | `mech_radiator` | Radiator | 6000 | No | Radiator repair; craftable |
| `alternator` | `mech_alternator` | Alternator | 5000 | No | Alternator repair; craftable |
| `car_battery` | `mech_car_battery` | Car Battery | 15000 | Yes | Battery replacement (workflow or quick); craftable |
| `fuel_pump` | `mech_fuel_pump` | Fuel Pump | 2000 | No | Fuel pump repair; craftable |
| `brake_discs` | `mech_brake_discs` | Brake Discs | 10000 | No | Brake disc repair (2); craftable |
| `shock_absorber` | `mech_shock_absorber` | Shock Absorber | 3000 | No | Suspension repair (4); craftable |
| `turbocharger` | `mech_turbocharger` | Turbocharger | 8000 | No | Turbo repair |
| `ev_battery_module` | `mech_ev_battery_module` | EV Battery Module | 20000 | No | Traction battery repair (2) |
| `ev_motor` | `mech_ev_motor` | Electric Motor | 30000 | No | Electric motor repair |
| `ev_coolant` | `mech_ev_coolant` | EV Battery Coolant | 2000 | No | Battery coolant service |
| `car_door` | `mech_car_door` | Car Door | 15000 | No | Door repair; craftable |
| `car_hood` | `mech_car_hood` | Car Hood | 12000 | No | Hood repair; craftable |
| `car_trunk` | `mech_car_trunk` | Trunk Lid | 10000 | No | Trunk lid repair; craftable |
| `car_bumper` | `mech_car_bumper` | Bumper | 6000 | No | Bumper repair; craftable |
| `car_glass` | `mech_car_glass` | Car Glass | 8000 | No | Window repair |
| `car_headlight` | `mech_car_headlight` | Headlight | 2000 | No | Headlight repair; craftable |
| `car_wheel` | `mech_car_wheel` | Wheel | 15000 | Yes | Missing wheel repair, quick wheel replacement |
| `body_panel` | `mech_body_panel` | Body Panel | 10000 | No | Bodywork (1–3), fuel tank; craftable |
| `obd_scanner` | `mech_obd_scanner` | OBD Scanner | 800 | Yes | Diagnostics (required tool) |
| `toolbox` | `mech_toolbox` | Toolbox | 6000 | Yes | Tool for most repairs, crafting and scrapping; placeable on the ground |
| `impact_wrench` | `mech_impact_wrench` | Impact Wrench | 3000 | No | Tool for wheel, brake, suspension, engine and transmission work |
| `car_jack` | `mech_car_jack` | Car Jack | 8000 | Yes | Jack up one wheel; flat-tyre mission tool |
| `jump_starter` | `mech_jump_starter` | Jump Starter | 4000 | Yes | Jump start a dead battery (anyone); craftable |
| `slim_jim` | `mech_slim_jim` | Slim Jim | 200 | Yes | Unlock locked vehicles (perm `tow`); craftable |
| `tuning_laptop` | `mech_tuning_laptop` | Tuning Laptop | 2500 | No | Tool for engine, transmission and turbo tuning (calibration) |
| `spray_gun` | `mech_spray_gun` | Spray Gun | 1500 | No | Tool for painting |
| `service_book` | `mech_service_book` | Service Book | 200 | Yes | Read the service history of a nearby vehicle |
| `repair_kit` | `mech_repair_kit` | Repair Kit | 3000 | Yes | Engine quick fix (anyone); craftable |
| `advanced_repair_kit` | `mech_advanced_repair_kit` | Advanced Repair Kit | 5000 | Yes | Full repair (mechanics, police, ambulance); craftable |
| `patch_kit` | `mech_patch_kit` | Emergency Patch Kit | 1500 | Yes | Temporary fix of failed parts (anyone); craftable |
| `cleaning_kit` | `mech_cleaning_kit` | Cleaning Kit | 1000 | Yes | Wash the vehicle (anyone); craftable |
| `scrap_metal` | `mech_scrap_metal` | Scrap Metal | 1000 | No | Crafting material (salvage, missions) |
| `aluminium` | `mech_aluminium` | Aluminium | 500 | No | Crafting material |
| `rubber` | `mech_rubber` | Rubber | 500 | No | Crafting material |
| `plastic` | `mech_plastic` | Plastic | 300 | No | Crafting material |
| `electronics` | `mech_electronics` | Electronics | 200 | No | Crafting material |
| `used_oil` | `mech_used_oil` | Used Oil | 4500 | No | Salvage of oil changes; recycled into engine oil, shock absorbers |
| `traffic_cone` | `mech_traffic_cone` | Traffic Cone | 1500 | Yes | Placeable prop; craftable |
| `road_barrier` | `mech_road_barrier` | Road Barrier | 8000 | Yes | Placeable prop; craftable |
| `work_sign` | `mech_work_sign` | Work Sign | 3000 | Yes | Placeable prop; craftable |
| `engine_stage1` | `mech_engine_stage1` | Engine Upgrade Stage 1 | 8000 | No | Performance tuning |
| `engine_stage2` | `mech_engine_stage2` | Engine Upgrade Stage 2 | 9000 | No | Performance tuning |
| `engine_stage3` | `mech_engine_stage3` | Engine Upgrade Stage 3 | 10000 | No | Performance tuning |
| `engine_stage4` | `mech_engine_stage4` | Engine Upgrade Stage 4 | 12000 | No | Performance tuning |
| `brakes_stage1` | `mech_brakes_stage1` | Street Brakes | 8000 | No | Performance tuning |
| `brakes_stage2` | `mech_brakes_stage2` | Sport Brakes | 9000 | No | Performance tuning |
| `brakes_stage3` | `mech_brakes_stage3` | Race Brakes | 10000 | No | Performance tuning |
| `transmission_stage1` | `mech_transmission_stage1` | Street Transmission | 15000 | No | Performance tuning |
| `transmission_stage2` | `mech_transmission_stage2` | Sport Transmission | 16000 | No | Performance tuning |
| `transmission_stage3` | `mech_transmission_stage3` | Race Transmission | 17000 | No | Performance tuning |
| `suspension_stage1` | `mech_suspension_stage1` | Lowered Suspension | 10000 | No | Performance tuning |
| `suspension_stage2` | `mech_suspension_stage2` | Street Suspension | 11000 | No | Performance tuning |
| `suspension_stage3` | `mech_suspension_stage3` | Sport Suspension | 12000 | No | Performance tuning |
| `suspension_stage4` | `mech_suspension_stage4` | Competition Suspension | 13000 | No | Performance tuning |
| `armor_stage1` | `mech_armor_stage1` | Armor Upgrade 20% | 15000 | No | Performance tuning |
| `armor_stage2` | `mech_armor_stage2` | Armor Upgrade 40% | 20000 | No | Performance tuning |
| `armor_stage3` | `mech_armor_stage3` | Armor Upgrade 60% | 25000 | No | Performance tuning |
| `armor_stage4` | `mech_armor_stage4` | Armor Upgrade 80% | 30000 | No | Performance tuning |
| `armor_stage5` | `mech_armor_stage5` | Armor Upgrade 100% | 35000 | No | Performance tuning |
| `turbo_kit` | `mech_turbo_kit` | Turbo Kit | 12000 | No | Turbo tuning |
| `paint_can` | `mech_paint_can` | Car Paint | 2000 | No | Paint material |
| `bodykit_parts` | `mech_bodykit_parts` | Body Kit Parts | 10000 | No | Body-kit material |
| `rims` | `mech_rims` | Rims | 20000 | No | Rims and custom tyres material |
| `tyre_smoke_kit` | `mech_tyre_smoke_kit` | Tyre Smoke Kit | 1000 | No | Tyre smoke material |
| `xenon_kit` | `mech_xenon_kit` | Xenon Kit | 1500 | No | Xenon material |
| `neon_kit` | `mech_neon_kit` | Neon Kit | 2000 | No | Neon material |
| `window_tint` | `mech_window_tint` | Window Tint | 500 | No | Window tint material |
| `vinyl` | `mech_vinyl` | Vinyl Wrap | 1000 | No | Livery material |
| `interior_parts` | `mech_interior_parts` | Interior Parts | 5000 | No | Interior material |
| `horn` | `mech_horn` | Horn | 500 | No | Horn material |
| `plate_kit` | `mech_plate_kit` | Plate Kit | 500 | No | Plate style material |
| `supply_crate` | `mech_supply_crate` | Parts Delivery | 20000 | No | Supply-run crate (delivered at the supply point) |

---

## 8. Commands & keybinds

| Command / key | Who | Description |
|---|---|---|
| `/mechanicadmin` | Admins | Workshop creator |
| `/mechanicadminfix` | Admins | Full repair of the current or closest vehicle |
| `/mechsociety [job]` | Admins | Society-account diagnostics in the server console |
| `/mechbills` | Everyone | Open your unpaid mechanic bills (`Config.Billing.command`) |
| `F6` | Mechanics on duty | Mechanic menu (`Config.Keys.mechanicMenu`, rebindable in the FiveM key settings) |
| `X` | Mechanics | Cancel running repair, tuning installation, scene or placement (`Config.Keys.cancel`) |
| `G` | Everyone (marker mode) | Vehicle interaction menu (`BRIDGE.VehicleInteractKey`) |
| `E` | Drivers | Start a repair station (`Config.Stations.promptKey`) |
| `W` / `A` / `D` / `F` | Pushing | Push, steer, let go |
| `E`, scroll / `←` `→`, `Backspace` | Placing props | Place, rotate, cancel |
| `E`, scroll / `←` `→` (Shift = fine), `↑` `↓`, `Backspace` | Creator | Confirm, rotate, radius, cancel |

---

## 9. Exports

Every export returns **plain copies** (never live tables). Plates are trimmed strings, and fake-plate aliases are resolved to the real plate.

### 9.1 Server exports – vehicles

#### `SetVehicleNew(plate)` → `boolean`
Marks a vehicle as brand new: 5–60 km, all parts 100 %, clean origin. It works before the first drive (valid for 1 hour) and after it. Call it from your vehicle shop after a purchase.
```lua
if GetResourceState("pls_mechanic") == "started" then
    exports.pls_mechanic:SetVehicleNew(plate)
end
```

#### `GetVehicleMileage(plate)` → `number | nil`
Mileage in km (cache or database). `nil` when the vehicle has no data.
```lua
local km = exports.pls_mechanic:GetVehicleMileage("ABC 123")
```

#### `AddVehicleMileage(plate, km)` → `boolean`
Adds km **with wear** (service parts, overdue damage, ageing). `false` when the vehicle has no data or `km <= 0`.
```lua
exports.pls_mechanic:AddVehicleMileage(plate, 12.5)
```

#### `GetVehicleData(entityOrPlate)` → `table | nil`
- **Entity:** loads the data, or creates it the same way as the first drive (a not-owned vehicle gets a random used condition).
- **Plate:** reads the cache or the database only (owned vehicles).
- Returns `{ plate, model, class, mileage, ev, owned, service = { [part] = % }, core = { [part] = % }, origin = { [part] = "unknown" }, ext = { [source] = mods } }`.
```lua
local data = exports.pls_mechanic:GetVehicleData(vehicleEntity)
if data and data.core.engine < 40 then print("engine is critical") end
```

#### `SetVehiclePart(plate, kind, key, value)` → `boolean`
Sets a part of a loaded vehicle. `kind` = `"service"` or `"core"`, `value` is clamped to 0–100. `true` when the part exists on the vehicle. The change is pushed to the statebag and saved.
```lua
exports.pls_mechanic:SetVehiclePart(plate, "core", "battery", 0) -- dead battery
```

#### `SetPartOrigin(plate, key, origin)` → `boolean`
`origin = "unknown"` marks an installed stolen part (×1.5 wear, diagnostics badge). `nil` makes it clean.
```lua
exports.pls_mechanic:SetPartOrigin(plate, "turbo", "unknown")
```

#### `SetVehicleModifiers(plate, source, mods)` → `boolean`
Adds persistent modifiers from your resource:
- `mods = { handling = { [CHandlingData float field] = multiplier }, wear = { [partKey] = multiplier } }`.
- Handling multipliers are clamped to 0.1–5.0 and applied by the driver client. Wear multipliers are clamped to 0.1–10.0.
- Up to 32 entries per table and up to 16 sources per vehicle. `source` can have at most 32 characters.
- `mods = nil` removes the source.
```lua
exports.pls_mechanic:SetVehicleModifiers(plate, "my_ecu", {
    handling = { fInitialDriveForce = 1.08 },
    wear = { oil = 1.3, spark_plugs = 1.2 },
})
exports.pls_mechanic:SetVehicleModifiers(plate, "my_ecu", nil) -- remove
```

#### `SetPlateAlias(aliasPlate, realPlate)` → `boolean`
Registers a fake plate: data, history and records of `aliasPlate` belong to `realPlate`. Aliases live in memory only, so the owning resource sets them again after a restart. The call is refused for the plate of a registered owned vehicle, for alias chains, and for plates longer than 12 characters.
```lua
exports.pls_mechanic:SetPlateAlias("FAKE123", "REAL 456")
```

#### `ClearPlateAlias(aliasPlate)` → `boolean`
Removes a fake-plate alias.
```lua
exports.pls_mechanic:ClearPlateAlias("FAKE123")
```

#### `GetRealPlate(plate)` → `string`
The real plate: the alias resolved, or the plate itself.
```lua
local real = exports.pls_mechanic:GetRealPlate(GetVehicleNumberPlateText(veh))
```

#### `GetEntityPlate(entity)` → `realPlate, spoofed, visiblePlate`
The trusted real plate of a vehicle entity. Never read the real plate from `GetVehicleNumberPlateText`, because the owner client can set any text. `spoofed = true` when the plate text (with aliases resolved) isn't the trusted plate. A vehicle seen for the first time is recorded (`spoofed = false`).
```lua
local plate, spoofed = exports.pls_mechanic:GetEntityPlate(vehicle)
if spoofed then print("plate text was changed by the client") end
```

#### `SetTrustedPlate(entity, plate)` → `boolean`
Declares the plate of a vehicle spawned by **your server code**, for example a mission vehicle whose plate the owner client applies later. The settling period is skipped.
```lua
local veh = CreateVehicleServerSetter(model, "automobile", x, y, z, h)
SetVehicleNumberPlateText(veh, "JOB 001")
exports.pls_mechanic:SetTrustedPlate(veh, "JOB 001")
```

#### `GetInstalledTuning(plate)` → `{ [category] = stage }`
Stages of the performance parts installed by workshops, for example `{ engine = 3, turbo = 1 }`. Returns `{}` when there are none.
```lua
local tuning = exports.pls_mechanic:GetInstalledTuning(plate)
if (tuning.engine or 0) >= 3 then print("stage 3+ engine") end
```

### 9.2 Server exports – workshops

#### `GetItems()` → `{ [key] = itemName }`
A copy of `Config.Items`.
```lua
local items = exports.pls_mechanic:GetItems()
print(items.engine_oil) -- "mech_engine_oil"
```

#### `GetShop(shopId)` → `table | nil`
`{ id, name, kind = "legal"|"illegal", points = { { id, type, coords, heading, radius, data } }, settings }`
```lua
local shop = exports.pls_mechanic:GetShop(1)
```

#### `GetShops(kind?)` → `table[]`
All workshops sorted by id. `kind` = `"legal"`, `"illegal"` or `nil` (all).
```lua
for _, shop in ipairs(exports.pls_mechanic:GetShops("legal")) do print(shop.id, shop.name) end
```

#### `GetCurrentShopId(src)` → `number | nil`
The player's current workshop: the illegal workshop he stands in (with crew access), otherwise his duty workshop.
```lua
local shopId = exports.pls_mechanic:GetCurrentShopId(source)
```

#### `HasShopPermission(src, perm, shopId?)` → `ok, shopId`
Uses the same rules as the script itself: the grade matrix plus duty for legal workshops, crew access for illegal ones. `shopId = nil` means the current workshop.
```lua
local ok, shopId = exports.pls_mechanic:HasShopPermission(source, "repair_core")
```

#### `IsNearShopPoint(src, shopId, pointType, margin?)` → `boolean, point`
The player stands at a point of the given type (point radius plus `margin`, default 3 m).
```lua
local near, point = exports.pls_mechanic:IsNearShopPoint(source, shopId, "storage")
```

#### `GetStashId(shopId)` → `string | nil`
The stash ID of the workshop storage (`pls_mechanic_stash_<id>`, or `pls_mechanic_stash_<id>_<key>` for illegal workshops). Never send an illegal stash ID to players.
```lua
local stash = exports.pls_mechanic:GetStashId(shopId)
exports.ox_inventory:AddItem(stash, "mech_engine_oil", 5)
```

#### `RegisterPointType(key, def)` → `boolean`
Adds a workshop point type. Call it on the **server and the client**, and again after a `pls_mechanic` restart. Built-in types can't be replaced. `key` may have at most 32 characters (`[%w_]`).
- `def = { label, icon, radius (0.5–15, default 1.5), multiple (default true), kinds = { legal = true, illegal = true }, fields?, color? = { r, g, b } }`.
```lua
exports.pls_mechanic:RegisterPointType("paint_booth", {
    label = "Paint booth", icon = "fa-solid fa-spray-can", radius = 3.0, multiple = true,
    kinds = { legal = true },
})
```

#### `RefreshShopAccess(src?)` → `boolean`
Re-sends the private illegal workshops and crew permissions to one player, or to everyone when `nil`. Call it after crew changes.
```lua
exports.pls_mechanic:RefreshShopAccess(source)
```

#### `IsVehicleBusy(entity)` → `busy, reason`
`true` when a base system uses the vehicle right now. Server records decide. Statebags written by clients can only add a reason, never clear one. The reasons:

| Reason | Meaning |
|---|---|
| `tuning` | Tuning menu or installation |
| `towed` | The vehicle is on a flatbed (or attached to anything) |
| `towing` | The flatbed carries a vehicle |
| `lift` | On a lift |
| `jack` | On a jack |
| `repair` | A repair step is running |
| `mission` | Mission vehicle |
| `service` | Workshop service vehicle |

```lua
local busy, reason = exports.pls_mechanic:IsVehicleBusy(vehicle)
if busy then return print("vehicle busy: " .. reason) end
```

### 9.3 Client exports

#### `GetVehicleMileage(vehicle)` → `number | nil`
Mileage in km, including km not yet synced from the vehicle you drive.
```lua
local km = exports.pls_mechanic:GetVehicleMileage(cache.vehicle)
```

#### `GetVehicleData(vehicle)` → `table | nil`
A copy of the vehicle statebag `pls_mech` (see 10.3). `nil` when the vehicle has no data yet.
```lua
local data = exports.pls_mechanic:GetVehicleData(vehicle)
if data then print(("Oil life %.0f %%"):format(data.service.oil or 100)) end
```

#### `GetItems()` → `{ [key] = itemName }`
A copy of `Config.Items`.

#### `GetShop(shopId)` → `table | nil`
The same shape as the server `GetShop`.

#### `GetCurrentShopId()` → `number | nil`
Your duty workshop, or the illegal workshop you stand in.

#### `HasPermission(perm, shopId?)` → `boolean`
A UI check only; the server checks again.
```lua
if exports.pls_mechanic:HasPermission("tow") then --[[ show your option ]] end
```

#### `RegisterPointType(key, def)` → `boolean`
Client side of the server export. Use the same definition.

#### `RegisterPointAction(pointType, action)` → `boolean`
Adds an action (target or marker option) to a point type. The actions of a resource are removed when it stops.
- `action = { label, icon, perm?, canInteract = function(shop, point) end, onSelect = function(shop, point) end }`.
- `shop` and `point` are copies. The callbacks run in `pcall`.
```lua
exports.pls_mechanic:RegisterPointAction("computer", {
    label = "Parts price list", icon = "fa-solid fa-list", perm = "order",
    onSelect = function(shop, point) OpenMyPriceList(shop.id) end,
})
```

#### `IsBusy()` → `boolean`
`true` while the base resource runs a repair workflow, diagnostics, the tuning menu or installation, an animation phase, a menu scene, or waits for parts.
```lua
if exports.pls_mechanic:IsBusy() then return end
```

#### `SetExternalPower(active)`
Your resource controls the engine power right now (for example a nitro boost). While active, the base skips its worn-engine power reduction.
```lua
exports.pls_mechanic:SetExternalPower(true)
-- ... boost ...
exports.pls_mechanic:SetExternalPower(false)
```

#### `useItem(data, slot)`
ox_inventory item callback (`client = { export = 'pls_mechanic.useItem' }`). It is used by the item definitions and is not meant to be called manually.

---

## 10. Open hooks & integration points

### 10.1 `configs/client.lua`

| Hook | Called when |
|---|---|
| `Config.OpenBossMenu(shopId, job)` | A player uses the boss-menu point (perm `bossmenu`) |
| `Config.SetFuel(vehicle, fuel)` | Mission vehicles are emptied or refuelled, a service vehicle or supply van spawns (100), an EV battery drains |
| `Config.GiveKeys(vehicle, plate)` | A service vehicle or supply van spawns, a slim-jim unlock succeeds (`Config.Unlock.giveKeys`) |
| `Config.UnlockDispatch(vehicle, coords)` | A slim-jim unlock is attempted (`nil` = off) |

```lua
Config.GiveKeys = function(vehicle, plate)
    TriggerEvent("vehiclekeys:client:SetOwner", plate)
end
Config.UnlockDispatch = function(vehicle, coords)
    exports["ps-dispatch"]:VehicleTheft(vehicle)
end
```

### 10.2 `server/open.lua`

| Hook | Default | Description |
|---|---|---|
| `OpenServer.ImpoundVehicle(src, entity, plate)` → `boolean` | Deletes the entity | Impound in your garage system. `plate` is the real plate. |
| `OpenServer.OnBillPaid(bill)` | Empty | After every paid bill. `bill = { id, shopId, mechanic, mechanicName, customer, customerName, plate, lines, note, total, commission, method, paidAt }` (illegal: `illegal = true`) |
| `OpenServer.Log(src, action, message, data)` | Empty | Discord or other logs. Actions include `creator_create`, `creator_update`, `creator_delete`, `creator_owner`, `creator_reset_permissions`, `settings_save`, `duty_on`, `duty_off`, `deposit`, `service_vehicle_spawn`, `service_vehicle_return`, `repair`, `repair_kit`, `lift_raise`, `lift_lower`, `jack_place`, `jack_remove`, `tuning`, `supply_order`, `supply_run_start`, `supply_crates`, `supply_take_crate`, `craft`, `fetch`, `bill_create`, `bill_paid`, `bill_declined`, `bill_society_failed`, `push`, `flip`, `unlock`, `impound`, `tow_attach`, `tow_detach`, `jumpstart`, `mission_start`, `mission_complete`, `prop_place`, `prop_pickup`, `station_repair`, `admin_fix` |
| `OpenServer.OnDutyChanged(src, onDuty, shop, job)` | Empty (commented pls_bossmenu example) | After every real clock in / out. `shop` is nil when the workshop was removed, `job` is the player's job. Use it to track duty time in a boss menu (`exports.pls_bossmenu:SetDuty(src, job, onDuty)`) |
| `OpenServer.OpenCustomCrafting(src, shopId)` → `boolean` | `false` | Return `true` to block the built-in workbench and open your own |

```lua
OpenServer.ImpoundVehicle = function(src, entity, plate)
    exports["your_garage"]:SetVehicleImpounded(plate)
    DeleteEntity(entity)
    return true
end
```

### 10.3 Statebags & GlobalState (read-only for other scripts)

| Bag | Key | Shape |
|---|---|---|
| Vehicle | `pls_mech` | `{ plate (visible plate), model, class, mileage, ev, owned, service = { [part] = life % }, core = { [part] = health % }, origin = { [part] = "unknown" }, ext = { [source] = { handling, wear } } }` |
| Vehicle | `pls_lift` | `{ shopId, pointId, base? }` while on a lift (`base` only for illegal workshops) |
| Vehicle | `pls_jack` | `{ wheel = "lf"/"rf"/"lr"/"rr", by = serverId }` |
| Vehicle | `pls_towed` | Net ID of the vehicle loaded on this flatbed |
| Vehicle | `pls_mission` | `{ id, type, owner, plate, setup }` for NPC mission vehicles |
| Vehicle | `pls_mech_service` | `{ owner, shopId, plate }` for service vehicles |
| Vehicle | `pls_supply` | `{ runId, shopId, crates }` for supply vans |
| Vehicle | `pls_mechanic_revert` | `{ id, state, plate }` unconfirmed tuning preview to revert, applied and cleared by the client with network control |
| Vehicle | `fuel` | Set by the default `Config.SetFuel` |
| Object | `pls_prop` | `{ owner = charId, item }` for placed props |
| Player | `pls_mechanic_duty` | Shop id or `false` |
| Global | `pls_mechanic_shops` | List of legal workshops `{ id, name, kind, jobs, blip, points, permissions, settings }` |
| Global | `pls_mech_lift_<shopId>_<pointId>` | `{ height, netId?, base? = { x, y, z, h } }` |
| Global | `pls_mechanic_supply` | `{ ["<shopId>"] = orders awaiting pickup }` |

Statebags written by clients are **never trusted** by the server. Use the exports (for example `IsVehicleBusy`, `GetVehicleData`) for decisions.

### 10.4 Server events (local, `AddEventHandler`)

| Event | Arguments |
|---|---|
| `pls_mechanic:server:shopsLoaded` | – |
| `pls_mechanic:server:shopsChanged` | `shopId, action` (`"create"` / `"update"` / `"delete"`) |
| `pls_mechanic:server:dutyChanged` | `src, shopId` (`false` when clocked out) |
| `pls_mechanic:server:repair:done` | `src, plate, kind, key, netId` |

```lua
AddEventHandler("pls_mechanic:server:repair:done", function(src, plate, kind, key)
    print(("%s repaired %s:%s on %s"):format(src, kind, key, plate))
end)
```

---

## 11. Security & performance

**Security**
- **Server-authoritative.** Clients only request actions. The server checks permission, duty, workshop, distance, location (bay, lift, jack), vehicle state, tools and items for every action, and applies the results itself.
- **Minimum work times.** Repair steps and kits need ≥ 90 % of their duration, tuning steps ≥ 90 %, crafting ≥ 85 %, mission actions ≥ 80 %, and unlock, impound and jump start ≥ 90 %. Faster requests are rejected.
- **Secure events.** Net events are sent with `TriggerSecureEvent` and verified with `CanTrustPlayer` (duty, mileage, collisions, lifts, props, tuning, missions).
- **Rate limits.** Every callback has a per-player cooldown (creator, settings, deposit, orders, runs, bills, menu actions, missions, props, lifts, jacks).
- **Mileage anti-cheat.** Reports are clamped to what `maxSpeed` allows for the elapsed time. Collision severity is clamped. The vehicle class sent by the client is validated against the server vehicle type.
- **Plate-spoof protection.** Trusted plates per entity, and fake plates only through server aliases.
- **Anti-duplication.** Performance parts are returned only if a workshop installed them. Jacks and flatbed state are server records. Failed item removals are rolled back. Supply orders use atomic status updates.
- **Input sanitising.** Creator payloads (names, jobs, coordinates, fields, up to 150 points), bills (lines, prices, notes) and tuning values (mod index up to 300) are all sanitised.
- **Stash access.** The ox_inventory `openInventory` hook and the PLS stash check require the `storage` permission of that workshop. Illegal stashes use unguessable IDs and require the player to stand at a storage point.
- **Clean money only.** Payments use cash (`money`) and bank. Society payouts go to the workshop's first-job society, with a refund if the society account is missing. No dirty or black money is used.
- **Privacy.** Illegal workshops and their lift positions are never broadcast to non-members.

**Performance**
- Workshop data is shared once through GlobalState, and vehicle condition through the `pls_mech` statebag. There is no polling.
- Driving effects run only for the driver of a vehicle with a parts system. Mileage is reported every 60 s or 1 km.
- Owned vehicles are batch-saved (one transaction every 5 min, plus on leave, delete and shutdown). Not-owned vehicles expire from the cache.
- Target `canInteract` checks use cached shop copies and cached item counts.
- Props, particles and animations are networked only where needed (configurable).

---

## 12. FAQ

**How does a mechanic start repairing a car?**
1. Clock in at the duty point and make sure you have an OBD Scanner.
2. Use the target **Diagnose vehicle** (or F6 → Diagnose).
3. In the report, tick the parts to replace and press **Start repair**.

Missing parts don't block the start as long as they are in the workshop storage: the workflow pauses and guides you to **Take parts for the job**.

**Why is a repair refused with "must be on a lift / in a bay"?**
Every part has a `location` in `configs/parts.lua`:
- engine, radiator, alternator, turbo, alignment, timing belt and bodywork need a **bay** (type repair or both) **or a lift**,
- transmission, clutch, fuel pump, suspension and the EV parts need a **lift**,
- brake pads, tyres and brake discs need a **lift or a jack** at the right wheel.

**How do I create a car lift?**
Run `/mechanicadmin`, edit the workshop, choose Points → add **Car lift**, place it where the car stands, set the radius and the height field (0.5–2.5 m) and save. Mechanics with `service` then use **Raise lift** or **Lower lift** on the point.

**How do I add money to the workshop account?**
Any employee (a player with one of the workshop jobs) can use **Deposit to workshop account** at a **computer** point (cash or bank, max $1 000 000). Paid bills, repair stations and the mission society share also go there. Withdrawals are done in your boss menu. If deposits fail, run `/mechsociety` and check that the society of the **first job** exists.

**What happens with NPC or stolen cars?**
A car that isn't owned gets a random used condition the first time it's driven (high mileage, worn parts, never critical). If it's registered as owned within 5 minutes and with less than 5 km driven, it counts as a shop purchase and becomes brand new. A stolen car registered later keeps its worn condition. Vehicle shops can call `exports.pls_mechanic:SetVehicleNew(plate)` for full reliability.

**Can a legal workshop use stolen parts?**
No (default `Config.StolenParts.legalAccepts = false`). Legal workshops only count and consume clean parts. Stolen parts can only be used in illegal workshops of the DLC, where the installed part gets the item's quality as its condition, wears 1.5× faster, and shows as "unknown origin" in legal diagnostics.

**How do I reopen a diagnostics report without scanning again?**
For 10 minutes after a scan (`Config.DiagnosticsReopen`), use the vehicle target **Open last diagnostics**, the option in the F6 menu, or use the OBD Scanner item and choose **Open last diagnostics**. The report opens with fresh data.

**Can customers repair their car themselves?**
Yes, in several ways:
- Place **repair stations** (paid, optionally only when no mechanic is on duty).
- Sell **Repair Kits**, **Patch Kits** and **Cleaning Kits**, which anyone can use.
- A **Jump Starter** works for anyone.
- The Advanced Repair Kit is limited to mechanics plus police and ambulance.

**How do I use my own impound, keys, fuel or boss menu?**
Edit `server/open.lua` (`OpenServer.ImpoundVehicle`) and `configs/client.lua` (`Config.GiveKeys`, `Config.SetFuel`, `Config.OpenBossMenu`). Both files are open.

**My NUI item images are missing.**
Copy `INSTALL/images/*.png` into your inventory image folder and set `Config.ImagePath` to match your inventory (ox_inventory: `nui://ox_inventory/web/images/%s.png`, qb-inventory: `nui://qb-inventory/html/images/%s.png`).

---

## 13. Version

| Version | Notes |
|---|---|
| **1.0.0** | Initial release: multi-workshop system with in-game creator, grade permissions, mileage-based vehicle model with EV support, OBD diagnostics, animated repair workflow with parts fetching, lifts and jacks, kits and quick repairs, repair stations, service book, performance and visual tuning with animated installation, customer tuning catalog with orders and quotes, supplier with supply runs, crafting, itemized billing, mechanic menu with flatbed towing, NPC missions, placeable props, illegal DLC integration. English and Czech. |

---

:speech_balloon: **Questions, bugs or ideas? [Join our Discord](https://discord.com/invite/HyNKsABYrb)** · :bug: GitHub Issues

**Polisek scripts**
