// Browser-only mock data for every view. Never imported by game logic (lazy dev chunk).
import type {
  BillCreateData,
  BillData,
  BillRecord,
  DiagnosticsData,
  HistoryData,
  ItemReq,
  Order,
  QuoteData,
  SettingsData,
  SupplierData,
  TuningCategory,
  TuningData,
  WorkflowData,
  WorkflowWaitingItem,
} from '../types'

const now = Math.floor(Date.now() / 1000)
const DAY = 86400

const req = (item: string, label: string, count: number, have: number): ItemReq => ({ item, label, count, have })
const toolbox = req('mech_toolbox', 'Toolbox', 1, 1)
const wrench = req('mech_impact_wrench', 'Impact wrench', 1, 1)
const jack = req('mech_car_jack', 'Car jack', 1, 0)

/* ----------------------------------------------------------------- diagnostics */

export const diagnostics: DiagnosticsData = {
  netId: 4121,
  plate: 'PLS 420',
  model: 'Karin Sultan RS',
  vehicleClass: 'Sports',
  mileage: 48213.6,
  ev: false,
  health: { engine: 612, body: 734, tank: 980 },
  service: [
    { key: 'oil', label: 'Engine oil & filter', life: 8, state: 'failed', nextServiceKm: -64, obd: 'P0520', items: [req('mech_engine_oil', 'Engine oil', 1, 2), req('mech_oil_filter', 'Oil filter', 1, 1)], tools: [toolbox], location: 'anywhere', canRepair: true },
    { key: 'air_filter', label: 'Air filter', life: 34, state: 'critical', nextServiceKm: 510, obd: 'P0101', items: [req('mech_air_filter', 'Air filter', 1, 0)], tools: [toolbox], location: 'anywhere', canRepair: true },
    { key: 'fuel_filter', label: 'Fuel filter', life: 62, state: 'worn', nextServiceKm: 1240, obd: 'P0171', items: [req('mech_fuel_filter', 'Fuel filter', 1, 3)], tools: [toolbox], location: 'anywhere', canRepair: true },
    { key: 'spark_plugs', label: 'Spark plugs', life: 71, state: 'optimal', nextServiceKm: 1775, obd: 'P0301', items: [req('mech_spark_plugs', 'Spark plugs', 1, 4)], tools: [toolbox], location: 'anywhere', canRepair: true },
    { key: 'coolant', label: 'Coolant', life: 88, state: 'optimal', nextServiceKm: 2640, obd: 'P0128', items: [req('mech_coolant', 'Coolant', 1, 2)], tools: [], location: 'anywhere', canRepair: true },
    { key: 'brake_fluid', label: 'Brake fluid', life: 55, state: 'worn', nextServiceKm: 1650, items: [req('mech_brake_fluid', 'Brake fluid', 1, 1)], tools: [], location: 'anywhere', canRepair: true },
    { key: 'transmission_fluid', label: 'Transmission fluid', life: 47, state: 'worn', nextServiceKm: 1880, obd: 'P0711', items: [req('mech_transmission_fluid', 'Transmission fluid', 1, 1)], tools: [toolbox], location: 'bay', canRepair: true },
    { key: 'brake_pads', label: 'Brake pads', life: 19, state: 'critical', nextServiceKm: 285, items: [req('mech_brake_pads', 'Brake pads', 4, 2)], tools: [wrench, jack], location: 'lift_or_jack', canRepair: true },
    { key: 'tyres', label: 'Tyres', life: 76, state: 'optimal', nextServiceKm: 1520, items: [req('mech_tyre', 'Tyre', 4, 4)], tools: [wrench, jack], location: 'lift_or_jack', canRepair: true },
    { key: 'timing_belt', label: 'Timing belt', life: 41, state: 'worn', nextServiceKm: 2460, obd: 'P0016', items: [req('mech_timing_belt', 'Timing belt', 1, 0)], tools: [toolbox], location: 'bay', canRepair: false, reason: 'You need the "service" permission.' },
  ],
  core: [
    { key: 'engine', label: 'Engine', health: 58, state: 'worn', obd: 'P0300', items: [req('mech_engine_parts', 'Engine parts', 2, 1)], tools: [toolbox, wrench], location: 'bay', canRepair: true },
    { key: 'transmission', label: 'Transmission', health: 91, state: 'optimal', obd: 'P0700', items: [req('mech_transmission_parts', 'Transmission parts', 1, 0)], tools: [toolbox], location: 'lift', canRepair: true },
    { key: 'clutch', label: 'Clutch', health: 44, state: 'worn', obd: 'P0806', items: [req('mech_clutch_kit', 'Clutch kit', 1, 1)], tools: [toolbox], location: 'lift', canRepair: true, unknownOrigin: true },
    { key: 'radiator', label: 'Radiator', health: 32, state: 'critical', obd: 'P0217', items: [req('mech_radiator', 'Radiator', 1, 1)], tools: [toolbox], location: 'bay', canRepair: true },
    { key: 'alternator', label: 'Alternator', health: 88, state: 'optimal', obd: 'P0562', items: [req('mech_alternator', 'Alternator', 1, 0)], tools: [toolbox], location: 'bay', canRepair: true },
    { key: 'battery', label: 'Battery', health: 11, state: 'failed', obd: 'P0560', items: [req('mech_car_battery', 'Car battery', 1, 1)], tools: [], location: 'anywhere', canRepair: true },
    { key: 'fuel_pump', label: 'Fuel pump', health: 76, state: 'optimal', obd: 'P0087', items: [req('mech_fuel_pump', 'Fuel pump', 1, 0)], tools: [toolbox], location: 'lift', canRepair: true },
    { key: 'brakes', label: 'Brake discs', health: 67, state: 'worn', obd: 'C0035', items: [req('mech_brake_discs', 'Brake discs', 4, 4)], tools: [wrench, jack], location: 'lift_or_jack', canRepair: true },
    { key: 'suspension', label: 'Suspension', health: 81, state: 'optimal', items: [req('mech_shock_absorber', 'Shock absorber', 4, 2)], tools: [wrench], location: 'lift', canRepair: false, reason: 'Requires the "repair_core" permission.' },
    { key: 'turbo', label: 'Turbocharger', health: 71, state: 'optimal', obd: 'P0299', items: [req('mech_turbocharger', 'Turbocharger', 1, 0)], tools: [toolbox], location: 'bay', canRepair: true },
  ],
  body: [
    { key: 'door:0', label: 'Front left door', items: [req('mech_car_door', 'Car door', 1, 1)], tools: [toolbox], location: 'anywhere', canRepair: true },
    { key: 'window:1', label: 'Front right window', items: [req('mech_car_glass', 'Car glass', 1, 2)], tools: [toolbox], location: 'anywhere', canRepair: true },
    { key: 'headlight', label: 'Headlights', items: [req('mech_car_headlight', 'Headlight', 1, 0)], tools: [toolbox], location: 'anywhere', canRepair: true },
    { key: 'tyre:1', label: 'Front right tyre (burst)', items: [req('mech_tyre', 'Tyre', 1, 4)], tools: [wrench], location: 'lift_or_jack', canRepair: true },
    { key: 'deformation', label: 'Bodywork deformation', items: [req('mech_body_panel', 'Body panel', 1, 1)], tools: [toolbox], location: 'bay', canRepair: false, reason: 'Vehicle must be in a repair bay.' },
  ],
  tuning: [
    { label: 'Engine', value: 'EMS Upgrade, Level 3' },
    { label: 'Brakes', value: 'Street Brakes' },
    { label: 'Transmission', value: 'Sport Transmission' },
    { label: 'Suspension', value: 'Lowered Suspension' },
    { label: 'Turbo', value: 'Turbo Tuning' },
    { label: 'Armor', value: 'Armor Upgrade 40%' },
    { label: 'Xenon lights', value: 'Ice Blue' },
    { label: 'Window tint', value: 'Dark Smoke' },
  ],
  faultCodes: [
    { code: 'P0520', description: 'Engine oil pressure sensor / switch circuit', part: 'oil' },
    { code: 'P0300', description: 'Random / multiple cylinder misfire detected', part: 'Engine' },
    { code: 'P0217', description: 'Engine coolant over temperature condition', part: 'radiator' },
    { code: 'P0560', description: 'System voltage malfunction', part: 'battery' },
    { code: 'U0100', description: 'Lost communication with ECM / PCM', part: 'ECU' },
    { code: 'P0606', description: 'Non-original ECU software detected', part: '', severity: 'critical' },
  ],
}

/* ----------------------------------------------------------------- workflow */

export const workflow: WorkflowData = {
  mode: 'repair',
  plate: 'PLS 420',
  cancelKey: 'X',
  current: 3,
  steps: [
    { id: 1, kind: 'service', key: 'oil', label: 'Engine oil & filter', status: 'done' },
    { id: 2, kind: 'service', key: 'air_filter', label: 'Air filter', status: 'failed', message: 'You are missing: Air filter' },
    {
      id: 3,
      kind: 'service',
      key: 'brake_pads',
      label: 'Brake pads',
      status: 'active',
      phase: { label: 'Removing the brake caliper', index: 2, count: 4, duration: 3500 },
    },
    { id: 4, kind: 'core', key: 'radiator', label: 'Radiator', status: 'pending' },
    { id: 5, kind: 'core', key: 'battery', label: 'Battery', status: 'pending' },
    { id: 6, kind: 'body', key: 'window:1', label: 'Front right window', status: 'pending' },
    { id: 7, kind: 'body', key: 'deformation', label: 'Bodywork deformation', status: 'skipped', message: 'Vehicle must be in a repair bay.' },
  ],
}

/** Long tuning installation (11 steps) – previews the tuning mode, phases and the scrolling list. */
export const workflowTuning: WorkflowData = {
  mode: 'tuning',
  plate: 'PLS 420',
  cancelKey: 'X',
  current: 1,
  steps: [
    { id: 1, kind: 'performance', key: 'engine', label: 'EMS Upgrade, Level 4', status: 'active' },
    { id: 2, kind: 'performance', key: 'turbo', label: 'Turbo Tuning', status: 'pending' },
    { id: 3, kind: 'performance', key: 'transmission', label: 'Race Transmission', status: 'pending' },
    { id: 4, kind: 'performance', key: 'brakes', label: 'Race Brakes', status: 'pending' },
    { id: 5, kind: 'performance', key: 'suspension', label: 'Competition Suspension', status: 'pending' },
    { id: 6, kind: 'performance', key: 'armor', label: 'Armor Upgrade 60%', status: 'pending' },
    { id: 7, kind: 'wheels', key: 'wheels', label: 'Rims – Sport "Deep Five"', status: 'pending' },
    { id: 8, kind: 'body', key: 'spoiler', label: 'Carbon Wing', status: 'pending' },
    { id: 9, kind: 'paint', key: 'paint_primary', label: 'Primary paint – Metallic Black', status: 'pending' },
    { id: 10, kind: 'lights', key: 'xenon', label: 'Xenon headlights – Ice Blue', status: 'pending' },
    { id: 11, kind: 'body', key: 'window_tint', label: 'Window tint – Limo', status: 'pending' },
  ],
}

type MockPhase = { label: string; duration: number }

/** Phases the dev runner plays per step key; `_repair` / `_tuning` are the fallbacks. duration 0 = indeterminate. */
export const workflowPhases: Record<string, MockPhase[]> = {
  oil: [
    { label: 'Draining the old oil', duration: 4000 },
    { label: 'Replacing the oil filter', duration: 3000 },
    { label: 'Filling new engine oil', duration: 3500 },
  ],
  brake_pads: [
    { label: 'Loosening the wheel nuts', duration: 2500 },
    { label: 'Removing the brake caliper', duration: 3500 },
    { label: 'Fitting new brake pads', duration: 4000 },
    { label: 'Tightening the wheel nuts', duration: 2500 },
  ],
  radiator: [
    { label: 'Draining the coolant', duration: 3000 },
    { label: 'Unbolting the old radiator', duration: 3500 },
    { label: 'Installing the new radiator', duration: 4000 },
    { label: 'Refilling the coolant', duration: 2500 },
  ],
  battery: [
    { label: 'Disconnecting the terminals', duration: 2000 },
    { label: 'Swapping the battery', duration: 3000 },
    { label: 'Connecting the terminals', duration: 2000 },
  ],
  'window:1': [
    { label: 'Removing the broken glass', duration: 3000 },
    { label: 'Fitting the new glass', duration: 4000 },
  ],
  engine: [
    { label: 'Opening the hood', duration: 1500 },
    { label: 'Connecting the laptop', duration: 2500 },
    { label: 'Flashing the ECU map', duration: 5000 },
    { label: 'Test run', duration: 2500 },
  ],
  paint_primary: [
    { label: 'Masking the bodywork', duration: 3000 },
    { label: 'Spraying the base coat', duration: 5000 },
    { label: 'Applying the clear coat', duration: 3500 },
  ],
  window_tint: [
    { label: 'Cleaning the windows', duration: 2500 },
    { label: 'Applying the tint film', duration: 4000 },
  ],
  _repair: [
    { label: 'Preparing the tools', duration: 2000 },
    { label: 'Replacing the part', duration: 3500 },
  ],
  _tuning: [
    { label: 'Fetching the part', duration: 0 },
    { label: 'Removing the stock part', duration: 3000 },
    { label: 'Installing the new part', duration: 3500 },
    { label: 'Tightening the bolts', duration: 2000 },
  ],
}

type MockWait = { timeout?: number; items: WorkflowWaitingItem[] }

/**
 * Parts fetching (mechanic-fetch-spec.md §6): steps whose parts are not carried yet – with "Fetch" on, the dev runner
 * pauses them, takes the parts one by one (restocks an empty storage) and resumes. timeout in s (default 600).
 * Covers: partial have, tools, low / empty / unknown stock, weight per piece, the red last minute (turbo).
 */
export const workflowWaiting: Record<string, MockWait> = {
  brake_pads: {
    items: [
      { key: 'mech_brake_pads', label: 'Brake pads', need: 4, have: 1, stock: 6, weight: 2.5 },
      { key: 'mech_impact_wrench', label: 'Impact wrench', need: 1, have: 0, stock: 0, tool: true, weight: 4 },
      { key: 'mech_car_jack', label: 'Car jack', need: 1, have: 1, stock: 2, tool: true, weight: 12 },
    ],
  },
  radiator: {
    items: [
      { key: 'mech_radiator', label: 'Radiator', need: 1, have: 0, stock: 3, weight: 14 },
      { key: 'mech_coolant', label: 'Coolant', need: 2, have: 0, stock: 1, weight: 5 },
    ],
  },
  battery: {
    items: [{ key: 'mech_car_battery', label: 'Car battery', need: 1, have: 0, stock: null, weight: 20 }],
  },
  engine: {
    items: [
      { key: 'mech_engine_stage4', label: 'Engine stage 4', need: 1, have: 0, stock: 2, weight: 35 },
      { key: 'mech_tuning_laptop', label: 'Tuning laptop', need: 1, have: 1, stock: 1, tool: true, weight: 3 },
    ],
  },
  turbo: {
    timeout: 70,
    items: [{ key: 'mech_turbo_kit', label: 'Turbo kit', need: 1, have: 0, stock: 0, weight: 28 }],
  },
  wheels: {
    items: [{ key: 'mech_rims', label: 'Rims', need: 4, have: 0, stock: 8, weight: 10 }],
  },
}

/* ----------------------------------------------------------------- history */

export const history: HistoryData = {
  plate: 'PLS 420',
  model: 'Karin Sultan RS',
  mileage: 48213.6,
  entries: [
    { id: 41, date: now - 3600, mileage: 48210, shopName: 'Bennys Motorworks', mechanic: 'Jake Morrison', type: 'service', label: 'Oil change', items: [{ label: 'Engine oil', count: 1 }, { label: 'Oil filter', count: 1 }] },
    { id: 40, date: now - 3500, mileage: 48210, shopName: 'Bennys Motorworks', mechanic: 'Jake Morrison', type: 'core', label: 'Radiator replaced', items: [{ label: 'Radiator', count: 1 }] },
    { id: 39, date: now - 3 * DAY, mileage: 47102, shopName: 'Hayes Autos', mechanic: 'Maria Lopez', type: 'tuning', label: 'EMS Upgrade, Level 3', items: [{ label: 'Engine stage 3', count: 1 }] },
    { id: 38, date: now - 3 * DAY - 600, mileage: 47102, shopName: 'Hayes Autos', mechanic: 'Maria Lopez', type: 'tuning', label: 'Paint – Metallic Black', items: [{ label: 'Paint can', count: 2 }] },
    { id: 37, date: now - 9 * DAY, mileage: 45880, shopName: 'Bennys Motorworks', mechanic: 'Jake Morrison', type: 'body', label: 'Front bumper replaced', items: [{ label: 'Car bumper', count: 1 }] },
    { id: 36, date: now - 12 * DAY, mileage: 45320, shopName: 'Roadside', mechanic: 'Tom Hughes', type: 'kit', label: 'Repair kit used', items: [{ label: 'Repair kit', count: 1 }] },
    { id: 35, date: now - 20 * DAY, mileage: 43995, shopName: 'Paleto Repair Station', mechanic: '—', type: 'station', label: 'Engine & body repair', items: [] },
    { id: 34, date: now - 26 * DAY, mileage: 42810, shopName: 'Bennys Motorworks', mechanic: 'Jake Morrison', type: 'service', label: 'Brake pads', items: [{ label: 'Brake pads', count: 4 }] },
    { id: 33, date: now - 26 * DAY - 900, mileage: 42810, shopName: 'Bennys Motorworks', mechanic: 'Jake Morrison', type: 'service', label: 'Spark plugs', items: [{ label: 'Spark plugs', count: 1 }] },
    { id: 32, date: now - 41 * DAY, mileage: 40120, shopName: 'Hayes Autos', mechanic: 'Maria Lopez', type: 'core', label: 'Battery replaced', items: [{ label: 'Car battery', count: 1 }] },
  ],
}

/* ----------------------------------------------------------------- billing */

export const billCreate: BillCreateData = {
  shopId: 1,
  shopName: 'Bennys Motorworks',
  plate: 'PLS 420',
  customers: [
    { serverId: 12, name: 'Adam Novák' },
    { serverId: 27, name: 'Lucy Carter' },
    { serverId: 43, name: 'Frank Delgado' },
  ],
  lines: [
    { label: 'Engine oil & filter', qty: 1, price: 295 },
    { label: 'Radiator', qty: 1, price: 1180 },
    { label: 'Front right window', qty: 1, price: 420 },
    { label: 'Labor', qty: 3, price: 150 },
  ],
  commission: 10,
  maxLines: 15,
}

export const bill: BillData = {
  id: 1042,
  shopName: 'Bennys Motorworks',
  mechanicName: 'Jake Morrison',
  plate: 'PLS 420',
  lines: billCreate.lines,
  total: 2345,
  note: 'Next oil change recommended in 800 km. Radiator comes with 30 days warranty.',
  methods: ['cash', 'bank'],
  balances: { cash: 1200, bank: 48250 },
}

/* ----------------------------------------------------------------- supplier */

const catalog: SupplierData['catalog'] = [
  { item: 'mech_engine_oil', label: 'Engine oil', price: 85, category: 'service', limit: 40, remaining: 32 },
  { item: 'mech_oil_filter', label: 'Oil filter', price: 45, category: 'service', limit: 40, remaining: 40 },
  { item: 'mech_air_filter', label: 'Air filter', price: 60, category: 'service' },
  { item: 'mech_fuel_filter', label: 'Fuel filter', price: 70, category: 'service' },
  { item: 'mech_spark_plugs', label: 'Spark plugs', price: 95, category: 'service' },
  { item: 'mech_coolant', label: 'Coolant', price: 55, category: 'service' },
  { item: 'mech_brake_pads', label: 'Brake pads', price: 140, category: 'service', limit: 20, remaining: 6 },
  { item: 'mech_tyre', label: 'Tyre', price: 180, category: 'service' },
  { item: 'mech_engine_parts', label: 'Engine parts', price: 1450, category: 'core', limit: 5, remaining: 2 },
  { item: 'mech_transmission_parts', label: 'Transmission parts', price: 1200, category: 'core', limit: 5, remaining: 5 },
  { item: 'mech_radiator', label: 'Radiator', price: 640, category: 'core' },
  { item: 'mech_alternator', label: 'Alternator', price: 520, category: 'core' },
  { item: 'mech_car_battery', label: 'Car battery', price: 310, category: 'core' },
  { item: 'mech_turbocharger', label: 'Turbocharger', price: 2800, category: 'core', limit: 2, remaining: 0 },
  { item: 'mech_car_door', label: 'Car door', price: 380, category: 'body' },
  { item: 'mech_car_glass', label: 'Car glass', price: 210, category: 'body' },
  { item: 'mech_car_bumper', label: 'Car bumper', price: 290, category: 'body' },
  { item: 'mech_body_panel', label: 'Body panel', price: 450, category: 'body' },
  { item: 'mech_toolbox', label: 'Toolbox', price: 650, category: 'tools' },
  { item: 'mech_impact_wrench', label: 'Impact wrench', price: 900, category: 'tools' },
  { item: 'mech_repair_kit', label: 'Repair kit', price: 350, category: 'kits' },
  { item: 'mech_paint_can', label: 'Paint can', price: 120, category: 'visual' },
  { item: 'mech_rims', label: 'Rims', price: 1100, category: 'visual' },
  { item: 'mech_scrap_metal', label: 'Scrap metal', price: 15, category: 'materials' },
]

const orders: Order[] = [
  { id: 88, date: now - 900, name: 'Jake Morrison', items: [{ item: 'mech_engine_oil', label: 'Engine oil', count: 10 }, { item: 'mech_oil_filter', label: 'Oil filter', count: 10 }], total: 1300, mode: 'delayed', status: 'pending', deliverAt: now + 14 * 60 },
  { id: 87, date: now - 4000, name: 'Maria Lopez', items: [{ item: 'mech_radiator', label: 'Radiator', count: 2 }, { item: 'mech_car_battery', label: 'Car battery', count: 3 }, { item: 'mech_tyre', label: 'Tyre', count: 8 }, { item: 'mech_coolant', label: 'Coolant', count: 6 }], total: 3968, mode: 'run', status: 'awaiting_pickup' },
  { id: 86, date: now - 7200, name: 'Jake Morrison', items: [{ item: 'mech_body_panel', label: 'Body panel', count: 4 }], total: 1440, mode: 'run', status: 'in_transit' },
  { id: 85, date: now - DAY, name: 'Maria Lopez', items: [{ item: 'mech_toolbox', label: 'Toolbox', count: 2 }], total: 1625, mode: 'instant', status: 'delivered', deliverAt: now - DAY },
  { id: 84, date: now - 2 * DAY, name: 'Tom Hughes', items: [{ item: 'mech_spark_plugs', label: 'Spark plugs', count: 12 }], total: 1140, mode: 'delayed', status: 'cancelled' },
]

export const supplier: SupplierData = {
  shopId: 1,
  shopName: 'Bennys Motorworks',
  payFrom: 'society',
  balance: 18450,
  catalog,
  modes: [
    { key: 'instant', label: 'Instant', multiplier: 1.25, enabled: true },
    { key: 'delayed', label: 'Delivery', multiplier: 1, minutes: 15, enabled: true },
    { key: 'run', label: 'Supply run', multiplier: 0.8, enabled: false },
  ],
  orders,
}

/* ----------------------------------------------------------------- tuning */

const levels = (names: string[], prices: number[], items: (ItemReq | undefined)[], installed: number): TuningCategory['options'] => [
  { value: -1, label: 'Stock', price: 0, installed: installed === -1 },
  ...names.map((label, i) => ({ value: i, label, price: prices[i] ?? 0, item: items[i], installed: installed === i })),
]

const palette = [
  ['Metallic Black', '#0d1116'], ['Metallic Graphite', '#1c1d21'], ['Metallic Black Steel', '#32383d'], ['Metallic Dark Silver', '#454b4f'],
  ['Metallic Silver', '#999da0'], ['Metallic Blue Silver', '#c2c4c6'], ['Metallic Steel Gray', '#979a97'], ['Metallic Shadow Silver', '#637380'],
  ['Metallic Red', '#c00e1a'], ['Metallic Torino Red', '#da1918'], ['Metallic Formula Red', '#b6111b'], ['Metallic Blaze Red', '#a51e23'],
  ['Metallic Garnet Red', '#7b1a22'], ['Metallic Candy Red', '#8e1b1f'], ['Metallic Sunset Red', '#6f1818'], ['Metallic Lava Red', '#b72f19'],
  ['Metallic Orange', '#f78616'], ['Metallic Race Yellow', '#ffcf20'], ['Metallic Bright Orange', '#f55f14'], ['Metallic Gold', '#c2944f'],
  ['Metallic Dark Green', '#132428'], ['Metallic Racing Green', '#122e2b'], ['Metallic Sea Green', '#12383c'], ['Metallic Lime Green', '#66b81f'],
  ['Metallic Midnight Blue', '#253aa7'], ['Metallic Dark Blue', '#1c3551'], ['Metallic Saxony Blue', '#4c5f81'], ['Metallic Blue', '#58688e'],
  ['Metallic Harbor Blue', '#2354a1'], ['Metallic Ultra Blue', '#2446a8'], ['Metallic Surf Blue', '#6ea3c6'], ['Metallic Bright Purple', '#6b1f7b'],
  ['Metallic Frost White', '#ffffff'], ['Metallic Ice White', '#f0f0f0'], ['Metallic Cream', '#cfc0a5'], ['Metallic Beige', '#d8b86a'],
  ['Matte Black', '#050505'], ['Matte Gray', '#121212'], ['Matte Light Gray', '#2f3233'], ['Matte Ice White', '#fcfcfc'],
].map(([label, hex], value) => ({ value, label: label!, hex: hex! }))

const paint = req('mech_paint_can', 'Paint can', 1, 3)
const sprayGun = req('mech_spray_gun', 'Spray gun', 1, 1)
const bodykit = req('mech_bodykit_parts', 'Bodykit parts', 1, 2)
const rims = req('mech_rims', 'Rims', 1, 0)
const laptop = req('mech_tuning_laptop', 'Tuning laptop', 1, 1)

export const tuning: TuningData = {
  netId: 4121,
  plate: 'PLS 420',
  model: 'Karin Sultan RS',
  categories: [
    { key: 'engine', label: 'Engine', group: 'performance', kind: 'list', current: 2, tool: laptop,
      options: levels(['EMS Upgrade, Level 1', 'EMS Upgrade, Level 2', 'EMS Upgrade, Level 3', 'EMS Upgrade, Level 4'], [4500, 9000, 13500, 22000],
        [req('mech_engine_stage1', 'Engine stage 1', 1, 0), req('mech_engine_stage2', 'Engine stage 2', 1, 0), req('mech_engine_stage3', 'Engine stage 3', 1, 0), req('mech_engine_stage4', 'Engine stage 4', 1, 1)], 2) },
    { key: 'brakes', label: 'Brakes', group: 'performance', kind: 'list', current: 0,
      options: levels(['Street Brakes', 'Sport Brakes', 'Race Brakes'], [2600, 5200, 8800], [req('mech_brakes_stage1', 'Brakes stage 1', 1, 0), req('mech_brakes_stage2', 'Brakes stage 2', 1, 1), req('mech_brakes_stage3', 'Brakes stage 3', 1, 0)], 0) },
    { key: 'transmission', label: 'Transmission', group: 'performance', kind: 'list', current: 1, tool: laptop,
      options: levels(['Street Transmission', 'Sport Transmission', 'Race Transmission'], [3000, 6500, 11000], [req('mech_transmission_stage1', 'Transmission stage 1', 1, 0), req('mech_transmission_stage2', 'Transmission stage 2', 1, 0), req('mech_transmission_stage3', 'Transmission stage 3', 1, 1)], 1) },
    { key: 'suspension', label: 'Suspension', group: 'performance', kind: 'list', current: -1,
      options: levels(['Lowered', 'Street', 'Sport', 'Competition'], [1500, 3200, 5400, 7800], [req('mech_suspension_stage1', 'Suspension stage 1', 1, 2), req('mech_suspension_stage2', 'Suspension stage 2', 1, 0), req('mech_suspension_stage3', 'Suspension stage 3', 1, 0), req('mech_suspension_stage4', 'Suspension stage 4', 1, 0)], -1) },
    { key: 'turbo', label: 'Turbo', group: 'performance', kind: 'toggle', current: false, price: 15000, item: req('mech_turbo_kit', 'Turbo kit', 1, 1), tool: laptop },
    { key: 'spoiler', label: 'Spoiler', group: 'body', kind: 'list', current: -1, item: bodykit,
      options: levels(['Carbon Lip', 'Ducktail', 'Low Wing', 'GT Wing', 'Drag Wing'], [800, 1200, 1900, 2800, 3400], [], -1) },
    { key: 'front_bumper', label: 'Front bumper', group: 'body', kind: 'list', current: 1, item: bodykit,
      options: levels(['Race Splitter', 'Carbon Bumper', 'Street Bumper'], [1400, 2100, 900], [], 1) },
    { key: 'exhaust', label: 'Exhaust', group: 'body', kind: 'list', current: -1, item: bodykit,
      options: levels(['Chrome Tip', 'Titanium Tuner', 'Big Bore', 'Twin Carbon'], [650, 1100, 1350, 2200], [], -1) },
    { key: 'hood', label: 'Hood', group: 'body', kind: 'list', current: -1, item: bodykit,
      options: levels(['Vented Hood', 'Carbon Hood', 'Race Hood'], [1100, 2400, 1900], [], -1) },
    { key: 'wheels_sport', label: 'Sport rims', group: 'wheels', kind: 'list', current: 4, item: rims,
      options: levels(['Inferno', 'Deep Five', 'Lozspeed Mk.V', 'Diamond Cut', 'Chrono', 'Feroci RR', 'FiftyNine', 'Mercie', 'Synthetic Z', 'Organic Type 0', 'Endo v.1', 'GT One', 'Duper 7', 'Uzer'], [1200, 2100, 2300, 2450, 2500, 2600, 2700, 2800, 3000, 3100, 3200, 3300, 3500, 3700], [], 4) },
    { key: 'wheels_muscle', label: 'Muscle rims', group: 'wheels', kind: 'list', current: -1, item: rims,
      options: levels(['Classic Five', 'Dukes', 'Muscle Freak', 'Kracka', 'Azreal', 'Mecha'], [1900, 2000, 2200, 2400, 2500, 2700], [], -99) },
    { key: 'wheels_tuner', label: 'Tuner rims', group: 'wheels', kind: 'list', current: -1, item: rims,
      options: levels(['Cosmo', 'Super Mesh', 'Outsider', 'Rollas', 'Driftmeister', 'Slicer'], [2100, 2300, 2400, 2600, 2800, 3000], [], -99) },
    { key: 'custom_tyres', label: 'Custom tyres', group: 'wheels', kind: 'toggle', current: false, price: 800, item: rims },
    { key: 'tyre_smoke', label: 'Tyre smoke', group: 'wheels', kind: 'toggle', current: true, price: 1500, item: req('mech_tyre_smoke_kit', 'Tyre smoke kit', 1, 1) },
    { key: 'tyre_smoke_color', label: 'Tyre smoke color', group: 'wheels', kind: 'rgb', current: { r: 255, g: 255, b: 255 }, price: 600, item: req('mech_tyre_smoke_kit', 'Tyre smoke kit', 1, 1) },
    { key: 'paint_primary', label: 'Primary color', group: 'paint', kind: 'color', current: 0, price: 1200, palette, item: paint, tool: sprayGun },
    { key: 'paint_secondary', label: 'Secondary color', group: 'paint', kind: 'color', current: 4, price: 900, palette, item: paint, tool: sprayGun },
    { key: 'paint_pearlescent', label: 'Pearlescent', group: 'paint', kind: 'color', current: 32, price: 800, palette, item: paint, tool: sprayGun },
    { key: 'paint_wheels', label: 'Wheel color', group: 'paint', kind: 'color', current: 4, price: 600, palette, item: paint, tool: sprayGun },
    { key: 'paint_type_primary', label: 'Primary finish', group: 'paint', kind: 'list', current: 1, item: paint, tool: sprayGun,
      options: [{ value: 0, label: 'Normal', price: 400 }, { value: 1, label: 'Metallic', price: 400, installed: true }, { value: 2, label: 'Pearl', price: 600 }, { value: 3, label: 'Matte', price: 700 }, { value: 4, label: 'Metal', price: 800 }, { value: 5, label: 'Chrome', price: 2500 }] },
    { key: 'xenon', label: 'Xenon lights', group: 'lights', kind: 'toggle', current: true, price: 1800, item: req('mech_xenon_kit', 'Xenon kit', 1, 0) },
    { key: 'xenon_color', label: 'Xenon color', group: 'lights', kind: 'color', current: 1, price: 300,
      palette: [{ value: 255, label: 'Stock', hex: '#dfe7ef' }, { value: 0, label: 'White', hex: '#ffffff' }, { value: 1, label: 'Blue', hex: '#2b6cff' }, { value: 2, label: 'Electric Blue', hex: '#00aaff' }, { value: 3, label: 'Mint Green', hex: '#5cffa8' }, { value: 4, label: 'Lime Green', hex: '#9bff2e' }, { value: 5, label: 'Yellow', hex: '#fff200' }, { value: 6, label: 'Golden Shower', hex: '#ffcf3a' }, { value: 7, label: 'Orange', hex: '#ff8a00' }, { value: 8, label: 'Red', hex: '#ff1e1e' }, { value: 9, label: 'Pony Pink', hex: '#ff6ec7' }, { value: 10, label: 'Hot Pink', hex: '#ff2d95' }, { value: 11, label: 'Purple', hex: '#8b2cff' }, { value: 12, label: 'Blacklight', hex: '#4b1cff' }] },
    { key: 'neon_layout', label: 'Neon layout', group: 'lights', kind: 'list', current: 0, item: req('mech_neon_kit', 'Neon kit', 1, 1),
      options: [{ value: 0, label: 'None', price: 0, installed: true }, { value: 3, label: 'Front and back', price: 900 }, { value: 12, label: 'Sides', price: 900 }, { value: 15, label: 'All around', price: 1500 }] },
    { key: 'neon_color', label: 'Neon color', group: 'lights', kind: 'rgb', current: { r: 255, g: 120, b: 0 }, price: 1200, item: req('mech_neon_kit', 'Neon kit', 1, 1) },
    { key: 'seats', label: 'Seats', group: 'interior', kind: 'list', current: -1, item: req('mech_interior_parts', 'Interior parts', 1, 1),
      options: levels(['Sport Seats', 'Bucket Seats', 'Racing Harness'], [900, 1500, 2100], [], -1) },
    { key: 'steering', label: 'Steering wheel', group: 'interior', kind: 'list', current: -1, item: req('mech_interior_parts', 'Interior parts', 1, 1),
      options: levels(['Leather Sport', 'Carbon Race', 'Suede Flat Bottom'], [600, 1100, 1300], [], -1) },
    { key: 'horn', label: 'Horn', group: 'other', kind: 'list', current: -1, item: req('mech_horn', 'Horn', 1, 2),
      options: levels(['Truck Horn', 'Police Horn', 'Clown Horn', 'Musical Horn 1', 'Sad Trombone'], [400, 450, 350, 600, 700], [], -1) },
    { key: 'window_tint', label: 'Window tint', group: 'other', kind: 'list', current: 1, item: req('mech_window_tint', 'Window tint', 1, 1),
      options: levels(['Pure Black', 'Dark Smoke', 'Light Smoke', 'Limo'], [700, 650, 500, 800], [], 1) },
    { key: 'plate', label: 'Plate style', group: 'other', kind: 'list', current: 0, item: req('mech_plate_kit', 'Plate kit', 1, 0),
      options: [{ value: 0, label: 'Blue on White 1', price: 0, installed: true }, { value: 1, label: 'Yellow on Black', price: 250 }, { value: 2, label: 'Yellow on Blue', price: 250 }, { value: 3, label: 'Blue on White 2', price: 250 }, { value: 4, label: 'Blue on White 3', price: 250 }, { value: 5, label: 'Yankton', price: 400 }] },
  ],
}

/* ----------------------------------------------------------------- tuning catalog (mechanic-catalog-spec.md §5) */

const catalogOrder = [
  { key: 'spoiler', value: 3 },
  { key: 'exhaust', value: 1 },
  { key: 'paint_primary', value: 8 },
  { key: 'neon_layout', value: 15 },
]

// Customer: the client builds the categories without item / tool, the pending order prefills the cart
export const tuningCustomer: TuningData = {
  ...tuning,
  mode: 'customer',
  shop: 'Bennys Motorworks',
  categories: tuning.categories.map((cat) => {
    const copy: TuningCategory = { ...cat, options: cat.options?.map((o) => ({ ...o, item: undefined })) }
    delete copy.item
    delete copy.tool
    return copy
  }),
  order: { changes: catalogOrder, total: 6600, minutes: 12 },
}

// Mechanic: the order wins over the saved cart (exhaust), the rest of the cart needs the customer's approval (brakes)
export const tuningOrder: TuningData = {
  ...tuning,
  mode: 'mechanic',
  shop: 'Bennys Motorworks',
  approvalEnabled: true,
  approvalTimeout: 60,
  order: { customer: 'Maria Lopez', changes: catalogOrder.slice(0, 2), total: 3900, minutes: 7 },
  draft: [
    { key: 'brakes', value: 2 },
    { key: 'exhaust', value: 3 },
  ],
}

// Mechanic confirmed with an extra – the client waits for the customer's answer to the quote
export const tuningWaiting: TuningData = { ...tuningOrder, approvalState: 'waiting' }

export const quote: QuoteData = {
  shop: 'Bennys Motorworks',
  mechanic: 'Jake Morrison',
  plate: 'PLS 420',
  items: [
    { label: 'Spoiler', value: 'GT Wing', price: 2800, ordered: true },
    { label: 'Exhaust', value: 'Titanium Tuner', price: 1100, ordered: true },
    { label: 'Brakes', value: 'Race Brakes', price: 8800, ordered: false },
  ],
  extraTotal: 8800,
  total: 12700,
  timeout: 60,
}

/* ----------------------------------------------------------------- settings */

const permissionKeys = [
  ['duty', 'Clock in / out'], ['diagnose', 'Diagnostics'], ['service', 'Service parts'], ['repair_core', 'Core parts'],
  ['repair_body', 'Bodywork'], ['tuning_performance', 'Performance tuning'], ['tuning_visual', 'Visual tuning'],
  ['storage', 'Storage'], ['craft', 'Crafting'], ['order', 'Supplier orders'], ['supply_run', 'Supply runs'],
  ['billing', 'Billing'], ['tow', 'Towing'], ['impound', 'Impound'], ['missions', 'NPC missions'],
  ['manage_shop', 'Workshop settings'], ['bossmenu', 'Boss menu'],
]

const defaultPerms: Record<number, string[]> = {
  0: ['duty', 'diagnose', 'service', 'storage', 'missions', 'tow'],
  1: ['duty', 'diagnose', 'service', 'repair_body', 'storage', 'missions', 'tow', 'billing', 'craft'],
  2: ['duty', 'diagnose', 'service', 'repair_core', 'repair_body', 'tuning_visual', 'storage', 'craft', 'supply_run', 'billing', 'tow', 'impound', 'missions'],
  3: ['duty', 'diagnose', 'service', 'repair_core', 'repair_body', 'tuning_performance', 'tuning_visual', 'storage', 'craft', 'order', 'supply_run', 'billing', 'tow', 'impound', 'missions'],
  4: permissionKeys.map(([key]) => key!),
}

const buildPerms = (grades: number[]) => {
  const result: Record<string, Record<string, boolean>> = {}
  grades.forEach((grade) => {
    const row: Record<string, boolean> = {}
    ;(defaultPerms[grade] ?? defaultPerms[3]!).forEach((perm) => (row[perm] = true))
    result[String(grade)] = row
  })
  return result
}

export const settings: SettingsData = {
  shopId: 1,
  shopName: 'Bennys Motorworks',
  canEdit: true,
  jobs: [
    { name: 'mechanic', label: 'Mechanic', grades: [{ grade: 0, label: 'Recruit' }, { grade: 1, label: 'Novice' }, { grade: 2, label: 'Experienced' }, { grade: 3, label: 'Advanced' }, { grade: 4, label: 'Boss' }] },
    { name: 'bennys', label: 'Bennys', grades: [{ grade: 0, label: 'Apprentice' }, { grade: 1, label: 'Tuner' }, { grade: 2, label: 'Owner' }] },
  ],
  permissions: { mechanic: buildPerms([0, 1, 2, 3, 4]), bennys: buildPerms([0, 1, 2]) },
  permissionList: permissionKeys.map(([key, label]) => ({ key: key!, label: label! })),
  settings: {
    laborMultiplier: 1,
    partsMarkup: 20,
    tuningMarkup: 0,
    commission: 10,
    supplyModes: { instant: true, delayed: true, run: false },
  },
}

const names = ['Jake Morrison', 'Maria Lopez', 'Tom Hughes']
const customers = ['Adam Novák', 'Lucy Carter', 'Frank Delgado', 'Eva Horáková', 'Chris Bell']
const statuses = ['paid', 'paid', 'paid', 'pending', 'declined']

export function billsPage(page: number): { bills: BillRecord[]; pages: number } {
  const bills: BillRecord[] = []
  for (let i = 0; i < 12; i++) {
    const id = 1042 - (page - 1) * 12 - i
    bills.push({
      id,
      date: now - (page - 1) * 5 * DAY - i * 9000,
      mechanic: names[id % names.length]!,
      customer: customers[id % customers.length]!,
      plate: i % 4 === 3 ? undefined : `${['PLS', 'LSC', 'BNY', 'RDX'][id % 4]} ${100 + ((id * 37) % 900)}`,
      total: 300 + ((id * 173) % 4200),
      status: statuses[id % statuses.length]!,
    })
  }
  return { bills, pages: 4 }
}

export function ordersPage(page: number): { orders: Order[]; pages: number } {
  return {
    orders: orders.map((o) => ({ ...o, id: o.id - (page - 1) * 5, date: o.date - (page - 1) * 3 * DAY })),
    pages: 3,
  }
}
