// NUI contract – mirrors mechanic-dev-spec.md §7. Keep in sync with the Lua modules.

export type View =
  | 'diagnostics'
  | 'workflow'
  | 'history'
  | 'billCreate'
  | 'bill'
  | 'supplier'
  | 'tuning'
  | 'settings'
  | 'quote'

export type FocusView = Exclude<View, 'workflow'>

export const FOCUS_VIEWS: FocusView[] = ['diagnostics', 'history', 'billCreate', 'bill', 'supplier', 'tuning', 'settings', 'quote']

export type PartState = 'optimal' | 'worn' | 'critical' | 'failed'
export type Location = 'anywhere' | 'bay' | 'lift' | 'lift_or_jack'

export interface ItemReq {
  item: string
  label: string
  count: number
  have: number
}

export interface Result {
  ok: boolean
  message?: string
}

export interface UiConfig {
  currency: string
  imagePath: string
  /** Config.MileageUnit – every distance from Lua is in km, the UI converts for "mi" (optional, default km) */
  mileageUnit?: 'km' | 'mi'
  /** Config.Fetch.enabled – missing parts do not block, they are fetched from the storage during the work (optional) */
  fetchParts?: boolean
}

export type Locales = Record<string, string>

export interface NuiMessage {
  action: 'open' | 'update' | 'close'
  view?: View
  data?: unknown
  locales?: Locales
  config?: Partial<UiConfig>
}

/* ----------------------------------------------------------------- diagnostics */

export interface ServicePart {
  key: string
  label: string
  life: number
  state: PartState
  nextServiceKm: number
  obd?: string
  items: ItemReq[]
  tools: ItemReq[]
  location: Location
  canRepair: boolean
  reason?: string
  /** installed from a stolen part (origin "unknown") – badge in the report */
  unknownOrigin?: boolean
}

export interface CorePart {
  key: string
  label: string
  health: number
  state: PartState
  obd?: string
  items: ItemReq[]
  tools: ItemReq[]
  location: Location
  canRepair: boolean
  reason?: string
  /** installed from a stolen part (origin "unknown") – badge in the report */
  unknownOrigin?: boolean
}

export interface BodyPart {
  key: string
  label: string
  items: ItemReq[]
  tools: ItemReq[]
  location: Location
  canRepair: boolean
  reason?: string
}

export interface FaultCode {
  code: string
  description: string
  /** part label / key, empty for codes of other resources (e.g. modified ECU software) */
  part: string
  /** only codes of other resources (pls_mechanic_illegal findings) */
  severity?: 'warning' | 'critical'
}

export interface DiagnosticsData {
  netId: number
  plate: string
  model: string
  vehicleClass: string
  mileage: number
  ev: boolean
  health: { engine: number; body: number; tank: number }
  service: ServicePart[]
  core: CorePart[]
  body: BodyPart[]
  tuning: { label: string; value: string }[]
  faultCodes: FaultCode[]
}

export type StepKind = 'service' | 'core' | 'body'

export interface RepairStep {
  kind: StepKind
  key: string
}

/* -------------------------------------------------------------------- workflow */

/** `waiting` = the step is paused until its parts are fetched from the workshop storage (mechanic-fetch-spec.md §6). */
export type StepStatus = 'pending' | 'active' | 'waiting' | 'done' | 'failed' | 'skipped'

/** Who runs the overlay – picks title, icon and cancel text (missing = repair). */
export type WorkflowMode = 'repair' | 'tuning'

/** Current work phase of the active step (mechanic-anim-spec.md §2). */
export interface WorkflowPhase {
  label: string
  /** 1-based index of the phase inside the step */
  index: number
  count: number
  /** ms – the progress bar runs from the moment the update arrived (<= 0 = indeterminate) */
  duration: number
  /** NUI-internal, never sent by Lua: performance.now() when this phase first arrived (set by App) */
  startedAt?: number
}

export interface WorkflowStep {
  id: number
  kind: string
  key: string
  label: string
  status: StepStatus
  message?: string
  /** only on the active step, missing = no phase running */
  phase?: WorkflowPhase
}

/** One part / tool of the waiting step (Fetch.GetOverlay, mechanic-fetch-spec.md §6). */
export interface WorkflowWaitingItem {
  key: string
  label: string
  need: number
  have: number
  /** count in the workshop storage, null/undefined = unknown */
  stock?: number | null
  tool?: boolean
  /** kg per piece, optional */
  weight?: number
}

/** "Waiting for parts" panel – the step lacks parts, the mechanic fetches them and resumes via the vehicle target. */
export interface WorkflowWaiting {
  /** step label */
  label: string
  items: WorkflowWaitingItem[]
  /** everything in the inventory -> continue via the target on the vehicle */
  ready: boolean
  /** localized hint from Lua */
  hint: string
  /** seconds until the wait times out */
  remaining?: number
  /** NUI-internal, never sent by Lua: performance.now() when `remaining` arrived (set by mergeWorkflow) */
  receivedAt?: number
}

export interface WorkflowData {
  mode?: WorkflowMode
  plate: string
  cancelKey: string
  /** optional second footer line, e.g. "or use the target on the vehicle" */
  cancelHint?: string
  current: number | null
  steps: WorkflowStep[]
  /** sent with every update while a step waits for parts, missing / null = not waiting */
  waiting?: WorkflowWaiting | null
}

/* --------------------------------------------------------------------- history */

export type HistoryType = 'service' | 'core' | 'body' | 'tuning' | 'kit' | 'station'

export interface HistoryEntry {
  id: number
  date: number
  mileage: number
  shopName: string
  mechanic: string
  type: HistoryType
  label: string
  items: { label: string; count: number }[]
}

export interface HistoryData {
  plate: string
  model?: string
  mileage: number
  entries: HistoryEntry[]
}

/* --------------------------------------------------------------------- billing */

export interface BillLine {
  label: string
  qty: number
  price: number
}

export interface BillCreateData {
  shopId: number
  shopName: string
  plate?: string
  customers: { serverId: number; name: string }[]
  lines: BillLine[]
  commission: number
  maxLines: number
  /** Config.Billing limits – optional, the server validates them anyway */
  maxLinePrice?: number
  maxTotal?: number
  maxNoteLength?: number
}

export type PayMethod = 'cash' | 'bank'

export interface BillData {
  id: number
  shopName: string
  mechanicName: string
  plate?: string
  lines: BillLine[]
  total: number
  note?: string
  methods: PayMethod[]
  balances: { cash: number; bank: number }
}

/* -------------------------------------------------------------------- supplier */

export type SupplyMode = 'instant' | 'delayed' | 'run'
export type OrderStatus = 'pending' | 'awaiting_pickup' | 'in_transit' | 'delivered' | 'cancelled'

export interface Order {
  id: number
  date: number
  name?: string
  items: { item: string; label: string; count: number }[]
  total: number
  mode: SupplyMode
  status: OrderStatus
  deliverAt?: number
}

export interface CatalogItem {
  item: string
  label: string
  price: number
  category: string
  limit?: number
  remaining?: number
}

export interface SupplierMode {
  key: SupplyMode
  label: string
  multiplier: number
  minutes?: number
  enabled: boolean
}

export interface SupplierData {
  shopId: number
  shopName: string
  payFrom: 'society' | 'player'
  balance: number
  catalog: CatalogItem[]
  modes: SupplierMode[]
  orders: Order[]
}

/* ---------------------------------------------------------------------- tuning */

export type TuningGroup = 'performance' | 'body' | 'wheels' | 'paint' | 'lights' | 'interior' | 'other'
export type TuningKind = 'list' | 'toggle' | 'color' | 'rgb'

export interface Rgb {
  r: number
  g: number
  b: number
}

export type TuningValue = number | boolean | Rgb

export interface TuningOption {
  value: number
  label: string
  price: number
  item?: ItemReq
  installed?: boolean
  /** back to stock / off – no material is consumed (optional, -1 and toggle off are detected without it) */
  removal?: boolean
}

export interface TuningCategory {
  key: string
  label: string
  group: TuningGroup
  kind: TuningKind
  current: TuningValue
  options?: TuningOption[]
  palette?: { value: number; label: string; hex: string }[]
  price?: number
  item?: ItemReq
  tool?: ItemReq
}

/** Pending customer order of the vehicle (mechanic-catalog-spec.md §3) – prefills the cart. */
export interface TuningOrder {
  /** customer name, mechanic mode only */
  customer?: string
  changes: { key: string; value: TuningValue }[]
  total: number
  /** minutes since the order was sent */
  minutes?: number
}

export interface TuningData {
  netId: number
  plate: string
  model: string
  categories: TuningCategory[]
  /** unconfirmed cart of this vehicle saved on last close (open only) */
  draft?: { key: string; value: TuningValue }[]
  /** "customer" = tuning catalog: no requirements, no draft, the cart is sent as an order (missing = mechanic) */
  mode?: 'mechanic' | 'customer'
  /** workshop label */
  shop?: string
  order?: TuningOrder
  /** Config.Tuning.Catalog approval – changes outside the order need the customer's approval */
  approvalEnabled?: boolean
  /** s – Config.Tuning.Catalog.approvalTimeout, tuning:confirm waits this long for the customer's answer (+ margin) */
  approvalTimeout?: number
  /** update while the client waits for the customer's answer to the quote */
  approvalState?: 'waiting' | false
}

export type CameraAction = 'rotateLeft' | 'rotateRight' | 'zoomIn' | 'zoomOut' | 'reset'

/* ----------------------------------------------------------------------- quote */

export interface QuoteItem {
  label: string
  /** server label of the value */
  value: string | number
  price: number
  /** false = extra work outside the customer's order */
  ordered: boolean
}

/** Customer approval of tuning outside their order (mechanic-catalog-spec.md §3.3). */
export interface QuoteData {
  shop: string
  mechanic: string
  plate: string
  items: QuoteItem[]
  extraTotal: number
  total: number
  /** s – no answer = declined */
  timeout: number
}

/* -------------------------------------------------------------------- settings */

export type PermissionMatrix = Record<string, Record<string, Record<string, boolean>>>

export interface ShopSettings {
  laborMultiplier: number
  partsMarkup: number
  tuningMarkup: number
  commission: number
  supplyModes: { instant: boolean; delayed: boolean; run: boolean }
}

export interface SettingsData {
  shopId: number
  shopName: string
  canEdit: boolean
  jobs: { name: string; label: string; grades: { grade: number; label: string }[] }[]
  permissions: PermissionMatrix
  permissionList: { key: string; label: string }[]
  settings: ShopSettings
}

export interface BillRecord {
  id: number
  date: number
  mechanic: string
  customer: string
  plate?: string
  total: number
  status: string
}

export interface BillsPage {
  bills: BillRecord[]
  pages: number
}

export interface OrdersPage {
  orders: Order[]
  pages: number
}

export type ViewDataMap = {
  diagnostics: DiagnosticsData
  workflow: WorkflowData
  history: HistoryData
  billCreate: BillCreateData
  bill: BillData
  supplier: SupplierData
  tuning: TuningData
  settings: SettingsData
  quote: QuoteData
}

/** Props every focused view receives from App. */
export interface ViewProps<T> {
  data: T
  onClose: () => void
}
