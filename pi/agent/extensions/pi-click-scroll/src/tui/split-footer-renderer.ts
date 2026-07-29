import {
  CURSOR_MARKER,
  sliceByColumn,
  truncateToWidth,
  visibleWidth,
  type Component,
  type TUI,
  type Terminal,
} from "@earendil-works/pi-tui";

export type StickySplitFooterDiagnostic = (event: string, fields: Record<string, unknown>) => void;

export interface StickySplitFooterViewportStatus {
  active: boolean;
  atBottom: boolean;
  followBottom: boolean;
  viewportTop: number;
  minimumViewportTop: number;
  maximumViewportTop: number;
  historyRows: number;
  historyLineCount: number;
}

export type StickySplitFooterViewportStatusChange = (status: StickySplitFooterViewportStatus | undefined) => void;

export interface StickySplitFooterRendererOptions {
  enabled: boolean;
  minimumHistoryRows: number;
  historyViewportLineLimit: number;
  diagnostic?: StickySplitFooterDiagnostic;
  onViewportStatusChange?: StickySplitFooterViewportStatusChange;
  formatMuted?: (text: string) => string;
  getToolsExpanded?: () => boolean;
}

export interface StickySplitFooterPatchStatus {
  installed: boolean;
  active: boolean;
  reason: string;
}

interface CursorPosition {
  row: number;
  col: number;
}

interface TuiWithInternals {
  children: Component[];
  terminal: Terminal;
  previousLines: string[];
  previousWidth: number;
  previousHeight: number;
  cursorRow: number;
  hardwareCursorRow: number;
  clearOnShrink: boolean;
  maxLinesRendered: number;
  previousViewportTop: number;
  fullRedrawCount: number;
  stopped: boolean;
  overlayStack: unknown[];
  hasOverlay?: () => boolean;
  extractCursorPosition?: (lines: string[], height: number) => CursorPosition | null;
  applyLineResets?: (lines: string[]) => string[];
  positionHardwareCursor?: (cursorPos: CursorPosition | null, totalLines: number) => void;
}

type DoRender = (this: TUI) => void;

interface PatchedTuiPrototype {
  doRender?: DoRender;
  __piStickyInputOriginalDoRender?: DoRender;
  __piStickyInputPatched?: boolean;
}

interface ChildRange {
  start: number;
  end: number;
}

interface RenderedChildren {
  lines: string[];
  ranges: ChildRange[];
  targets: Array<ExpandableComponent | undefined>;
}

interface RenderedHistoryCache {
  width: number;
  rootChildren: Component[];
  containers: Array<{ component: Component & { children: Component[] }; children: Component[] }>;
  rendered: RenderedChildren;
  tailComponent?: Component;
  tailLineCount: number;
  dirtyComponents: Set<Component>;
  volatileComponents: Set<Component>;
}

interface SplitLayout {
  logicalLineCount: number;
  footerStartLine: number;
  stickyRows: number;
  historyRows: number;
  historyViewportTop: number;
  screenLines: string[];
  historyTargets: Array<ExpandableComponent | undefined>;
}

interface ExpandableComponent extends Component {
  expanded?: boolean;
  _expanded?: boolean;
  isPartial?: boolean;
  setExpanded(expanded: boolean): void;
}

interface ViewportMetadata {
  footerStartLine: number;
  stickyRows: number;
  historyRows: number;
  historyViewportTop: number;
  logicalLineCount: number;
  historyTargets: Array<ExpandableComponent | undefined>;
}

interface HistoryViewportState {
  viewportTop: number;
  followBottom: boolean;
}

interface LineSpan {
  start: number;
  endExclusive: number;
}

interface TranscriptSelection {
  start: { row: number; column: number };
  end: { row: number; column: number };
}

interface ToolsExpansionState {
  expanded: boolean;
  targets: WeakSet<object>;
}

export interface StickySplitFooterScrollResult {
  handled: boolean;
  changed: boolean;
  viewportTop?: number;
  followBottom?: boolean;
}

interface UnsupportedLayout {
  reason: string;
  fields?: Record<string, unknown>;
}

const DEFAULT_OPTIONS: StickySplitFooterRendererOptions = {
  enabled: false,
  minimumHistoryRows: 3,
  historyViewportLineLimit: 200,
};

const STICKY_PANE_CHILD_COUNT = 5;
const SIXEL_RENDER_ROW_MARKER = "\x1b_Gm=0;\x1b\\";
const INLINE_IMAGE_PROTOCOL_MARKERS = [
  SIXEL_RENDER_ROW_MARKER,
  "\x1b_G", // Kitty graphics APC.
  "\x1b]1337;File=", // iTerm2 inline image OSC.
  "\x1bP", // Sixel DCS.
] as const;
const CURSOR_UP_ROWS_PATTERN = /\x1b\[(\d+)A/g;
const FORCED_COLLAPSED_PREVIEW_ROWS = 4;
const FORCED_COLLAPSED_ROW_LIMIT = FORCED_COLLAPSED_PREVIEW_ROWS + 2;

let options: StickySplitFooterRendererOptions = { ...DEFAULT_OPTIONS };
let patchInstalled = false;
let lastPatchReason = "not-installed";
let viewportStatusKeys = new WeakMap<object, string>();
let toolsExpansionStates = new WeakMap<object, ToolsExpansionState>();
let renderedHistoryCaches = new WeakMap<object, RenderedHistoryCache>();
let renderedComponentLineCounts = new WeakMap<object, number>();

const viewportMetadata = new WeakMap<object, ViewportMetadata>();
const componentToggleStrategies = new WeakMap<object, "native" | "compact">();
const compactedComponents = new WeakSet<object>();
const locallyToggledComponents = new WeakSet<object>();
const pendingStreamingComponents = new WeakSet<object>();
const historyViewportState = new WeakMap<object, HistoryViewportState>();
const followBottomOnNextAppend = new WeakSet<object>();
const toolsExpansionGenerations = new WeakMap<object, number>();
const transcriptSelections = new WeakMap<object, TranscriptSelection>();

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(value, max));
}

function getTuiInternals(tui: TUI): TuiWithInternals {
  return tui as unknown as TuiWithInternals;
}

function hasRequiredInternals(tui: TuiWithInternals): boolean {
  return Array.isArray(tui.children)
    && Array.isArray(tui.previousLines)
    && Array.isArray(tui.overlayStack)
    && typeof tui.extractCursorPosition === "function"
    && typeof tui.applyLineResets === "function"
    && typeof tui.positionHardwareCursor === "function"
    && typeof tui.terminal?.write === "function"
    && typeof tui.terminal.columns === "number"
    && typeof tui.terminal.rows === "number";
}

function getVisibleOverlayState(tui: TuiWithInternals): boolean {
  if (typeof tui.hasOverlay === "function") {
    return tui.hasOverlay();
  }

  return Array.isArray(tui.overlayStack) && tui.overlayStack.length > 0;
}

function getUnsupportedTerminalReason(tui: TuiWithInternals): UnsupportedLayout | undefined {
  const width = tui.terminal.columns;
  const height = tui.terminal.rows;

  if (!Number.isFinite(width) || !Number.isFinite(height)) {
    return { reason: "invalid-terminal-dimensions", fields: { width, height } };
  }

  if (width < 20 || height < 8) {
    return { reason: "terminal-too-small", fields: { width, height } };
  }

  if (process.env.TERM === "dumb") {
    return { reason: "dumb-terminal" };
  }

  if ((process.env.PI_CLAUDE_STYLE_SCROLL_DISABLE_SPLIT_FOOTER === "1" || process.env.PI_STICKY_INPUT_DISABLE_SPLIT_FOOTER === "1")) {
    return { reason: "disabled-by-environment" };
  }

  return undefined;
}

function findStickyPaneStartIndex(tui: TuiWithInternals): number {
  return tui.children.length >= STICKY_PANE_CHILD_COUNT
    ? tui.children.length - STICKY_PANE_CHILD_COUNT
    : -1;
}

function isPlainContainer(component: Component): component is Component & { children: Component[] } {
  return component.constructor?.name === "Container" && Array.isArray((component as { children?: unknown }).children);
}

function isExpandable(component: Component): component is ExpandableComponent {
  return typeof (component as Partial<ExpandableComponent>).setExpanded === "function";
}

function createForcedCollapsedLine(template: string, text: string, width: number): string {
  const inset = Math.min(2, width);
  const content = truncateToWidth(text, width - inset, "");
  const styledContent = content ? (options.formatMuted?.(content) ?? content) : content;
  return sliceByColumn(template, 0, inset)
    + styledContent
    + " ".repeat(Math.max(0, width - inset - visibleWidth(content)));
}

function rememberComponentRender(
  component: Component,
  rendered: { lines: string[]; targets: Array<ExpandableComponent | undefined> },
): { lines: string[]; targets: Array<ExpandableComponent | undefined> } {
  renderedComponentLineCounts.set(component as unknown as object, rendered.lines.length);
  return rendered;
}

function renderComponent(
  component: Component,
  width: number,
  inheritedTarget?: ExpandableComponent,
): { lines: string[]; targets: Array<ExpandableComponent | undefined> } {
  const target = isExpandable(component) ? component : inheritedTarget;
  if (!isPlainContainer(component)) {
    let lines: string[];
    if (target === component && compactedComponents.has(target)) {
      const expanded = getComponentExpanded(target);
      target.setExpanded(true);
      try {
        lines = component.render(width);
      } finally {
        target.setExpanded(expanded);
      }
    } else {
      lines = component.render(width);
    }
    if (target === component && compactedComponents.has(target) && lines.length > FORCED_COLLAPSED_ROW_LIMIT) {
      const hiddenRows = lines.length - FORCED_COLLAPSED_PREVIEW_ROWS;
      const hint = `... (${hiddenRows} more line${hiddenRows === 1 ? "" : "s"})`;
      lines = [
        ...lines.slice(0, FORCED_COLLAPSED_PREVIEW_ROWS),
        createForcedCollapsedLine(lines[FORCED_COLLAPSED_PREVIEW_ROWS] ?? "", hint, width),
        createForcedCollapsedLine(lines.at(-1) ?? "", "", width),
      ];
    }
    return rememberComponentRender(component, { lines, targets: lines.map(() => target) });
  }

  const lines: string[] = [];
  const targets: Array<ExpandableComponent | undefined> = [];
  for (const child of component.children) {
    const rendered = renderComponent(child, width, target);
    lines.push(...rendered.lines);
    targets.push(...rendered.targets);
  }
  return rememberComponentRender(component, { lines, targets });
}

function renderChildren(children: readonly Component[], width: number): RenderedChildren {
  const ranges: ChildRange[] = [];
  const lines: string[] = [];
  const targets: Array<ExpandableComponent | undefined> = [];

  for (const child of children) {
    const start = lines.length;
    const rendered = renderComponent(child, width);
    lines.push(...rendered.lines);
    targets.push(...rendered.targets);
    ranges.push({ start, end: lines.length });
  }

  return { lines, ranges, targets };
}

function sameComponents(left: readonly Component[], right: readonly Component[]): boolean {
  return left.length === right.length && left.every((component, index) => component === right[index]);
}

function collectPlainContainerSnapshots(
  components: readonly Component[],
  snapshots: RenderedHistoryCache["containers"] = [],
): RenderedHistoryCache["containers"] {
  for (const component of components) {
    if (!isPlainContainer(component)) continue;
    snapshots.push({ component, children: [...component.children] });
    collectPlainContainerSnapshots(component.children, snapshots);
  }
  return snapshots;
}

function getLastRenderedComponent(components: readonly Component[]): Component | undefined {
  return components.findLast(
    (component) => renderedComponentLineCounts.get(component as unknown as object) !== 0,
  );
}

function getTailComponent(components: readonly Component[]): Component | undefined {
  let component = getLastRenderedComponent(components);
  while (component && isPlainContainer(component) && component.children.length > 0) {
    component = getLastRenderedComponent(component.children);
  }
  return component;
}

function getStructuralTailComponent(components: readonly Component[]): Component | undefined {
  let component = components.at(-1);
  while (component && isPlainContainer(component) && component.children.length > 0) {
    component = component.children.at(-1);
  }
  return component;
}

function getLastAssistantMessageComponent(components: readonly Component[]): Component | undefined {
  for (let index = components.length - 1; index >= 0; index -= 1) {
    const component = components[index]!;
    if (component.constructor?.name === "AssistantMessageComponent") return component;
    if (isPlainContainer(component)) {
      const nested = getLastAssistantMessageComponent(component.children);
      if (nested) return nested;
    }
  }
  return undefined;
}

function isRunningUserBashComponent(component: Component): boolean {
  return component.constructor?.name === "BashExecutionComponent"
    && (component as { status?: unknown }).status === "running";
}

function getRunningUserBashComponents(components: readonly Component[], results: Component[] = []): Component[] {
  for (const component of components) {
    if (isRunningUserBashComponent(component)) results.push(component);
    if (isPlainContainer(component)) getRunningUserBashComponents(component.children, results);
  }
  return results;
}

function isTailContainer(components: readonly Component[], target: Component): boolean {
  for (let index = components.length - 1; index >= 0; index -= 1) {
    const component = components[index]!;
    if (component === target) return true;
    if (renderedComponentLineCounts.get(component as unknown as object) === 0) continue;
    return isPlainContainer(component) && isTailContainer(component.children, target);
  }
  return false;
}

function isTailHistoryComponent(tui: TuiWithInternals, target: Component): boolean {
  const footerStartIndex = findStickyPaneStartIndex(tui);
  return footerStartIndex >= 0
    && getTailComponent(tui.children.slice(0, footerStartIndex)) === target;
}

function isAppendOnly(previous: readonly Component[], current: readonly Component[]): boolean {
  return current.length > previous.length
    && previous.every((component, index) => component === current[index]);
}

function refreshPlainContainerLineCounts(components: readonly Component[]): number {
  let lineCount = 0;
  for (const component of components) {
    const componentLineCount = isPlainContainer(component)
      ? refreshPlainContainerLineCounts(component.children)
      : (renderedComponentLineCounts.get(component as unknown as object) ?? 0);
    renderedComponentLineCounts.set(component as unknown as object, componentLineCount);
    lineCount += componentLineCount;
  }
  return lineCount;
}

function findComponentLineRange(
  components: readonly Component[],
  target: Component,
  start = 0,
): { start: number; lineCount: number } | undefined {
  let offset = start;
  for (const component of components) {
    const lineCount = renderedComponentLineCounts.get(component as unknown as object) ?? 0;
    if (component === target) return { start: offset, lineCount };
    if (isPlainContainer(component)) {
      const nested = findComponentLineRange(component.children, target, offset);
      if (nested) return nested;
    }
    offset += lineCount;
  }
  return undefined;
}

function refreshCachedComponents(tui: TuiWithInternals, targets: readonly Component[]): boolean {
  const tuiKey = tui as unknown as object;
  const cached = renderedHistoryCaches.get(tuiKey);
  const footerStartIndex = findStickyPaneStartIndex(tui);
  if (!cached || footerStartIndex < 0 || cached.width !== tui.terminal.columns) return false;

  const rootChildren = tui.children.slice(0, footerStartIndex);
  if (!sameComponents(cached.rootChildren, rootChildren)) return false;
  if (cached.containers.some(({ component, children }) => !sameComponents(component.children, children))) return false;

  const replacements = [...new Set(targets)].map((target) => ({
    target,
    range: findComponentLineRange(rootChildren, target),
  }));
  if (replacements.some(({ range }) => !range)) return false;

  replacements.sort((left, right) => right.range!.start - left.range!.start);
  for (const { target, range } of replacements) {
    const rendered = renderComponent(target, cached.width);
    cached.rendered.lines.splice(range!.start, range!.lineCount, ...rendered.lines);
    cached.rendered.targets.splice(range!.start, range!.lineCount, ...rendered.targets);
  }

  refreshPlainContainerLineCounts(rootChildren);
  let line = 0;
  cached.rendered.ranges = rootChildren.map((component) => {
    const start = line;
    line += renderedComponentLineCounts.get(component as unknown as object) ?? 0;
    return { start, end: line };
  });
  cached.tailComponent = getTailComponent(rootChildren);
  cached.tailLineCount = cached.tailComponent
    ? (renderedComponentLineCounts.get(cached.tailComponent as unknown as object) ?? 0)
    : 0;
  for (const target of targets) {
    cached.dirtyComponents.delete(target);
    if (isRunningUserBashComponent(target)) cached.volatileComponents.add(target);
    else cached.volatileComponents.delete(target);
  }
  return true;
}

function appendToCachedHistory(
  cached: RenderedHistoryCache,
  rootChildren: readonly Component[],
  changedContainers: RenderedHistoryCache["containers"],
  width: number,
): boolean {
  if (changedContainers.length !== 1) return false;
  const changed = changedContainers[0];
  if (!changed || !isTailContainer(rootChildren, changed.component)) return false;
  if (!isAppendOnly(changed.children, changed.component.children)) return false;

  const appendedChildren = changed.component.children.slice(changed.children.length);
  const appended = renderChildren(appendedChildren, width);
  cached.rendered.lines.push(...appended.lines);
  cached.rendered.targets.push(...appended.targets);
  changed.children = [...changed.component.children];
  cached.containers.push(...collectPlainContainerSnapshots(appendedChildren));
  for (const component of getRunningUserBashComponents(appendedChildren)) cached.volatileComponents.add(component);
  refreshPlainContainerLineCounts(rootChildren);
  cached.tailComponent = getStructuralTailComponent(appendedChildren) ?? getTailComponent(rootChildren);
  cached.tailLineCount = cached.tailComponent
    ? (renderedComponentLineCounts.get(cached.tailComponent as unknown as object) ?? 0)
    : 0;
  return true;
}

function getRenderedHistory(
  tui: TuiWithInternals,
  width: number,
  footerStartIndex: number,
): RenderedChildren {
  const tuiKey = tui as unknown as object;
  const rootChildren = tui.children.slice(0, footerStartIndex);
  const cached = renderedHistoryCaches.get(tuiKey);
  if (cached && cached.width === width && sameComponents(cached.rootChildren, rootChildren)) {
    for (const component of cached.volatileComponents) cached.dirtyComponents.add(component);
    const changedContainers = cached.containers.filter(
      ({ component, children }) => !sameComponents(component.children, children),
    );
    if (changedContainers.length === 0) {
      const dirtyComponents = [...cached.dirtyComponents];
      if (dirtyComponents.length === 0) return cached.rendered;
      if (refreshCachedComponents(tui, dirtyComponents)) return cached.rendered;
    } else if (appendToCachedHistory(cached, rootChildren, changedContainers, width)) {
      const dirtyComponents = [...cached.dirtyComponents];
      if (dirtyComponents.length === 0 || refreshCachedComponents(tui, dirtyComponents)) {
        if (followBottomOnNextAppend.delete(tuiKey)) {
          historyViewportState.set(tuiKey, { viewportTop: 0, followBottom: true });
        }
        return cached.rendered;
      }
    }
  }

  const rendered = renderChildren(rootChildren, width);
  const tailComponent = getTailComponent(rootChildren);
  renderedHistoryCaches.set(tuiKey, {
    width,
    rootChildren,
    containers: collectPlainContainerSnapshots(rootChildren),
    rendered,
    tailComponent,
    tailLineCount: tailComponent
      ? (renderedComponentLineCounts.get(tailComponent as unknown as object) ?? 0)
      : 0,
    dirtyComponents: new Set(),
    volatileComponents: new Set(getRunningUserBashComponents(rootChildren)),
  });
  return rendered;
}

function getRetainedHistoryBounds(
  historyLineCount: number,
  historyRows: number,
): { minimumViewportTop: number; maximumViewportTop: number } {
  const maximumViewportTop = Math.max(0, historyLineCount - historyRows);
  const minimumViewportTop = options.historyViewportLineLimit < DEFAULT_OPTIONS.historyViewportLineLimit
    ? Math.max(0, historyLineCount - options.historyViewportLineLimit - historyRows)
    : 0;
  return { minimumViewportTop, maximumViewportTop };
}

function getHistoryViewportTop(
  tui: object,
  historyLineCount: number,
  historyRows: number,
): { viewportTop: number; followBottom: boolean } {
  const { minimumViewportTop, maximumViewportTop } = getRetainedHistoryBounds(historyLineCount, historyRows);
  const state = historyViewportState.get(tui);

  if (!state || state.followBottom) {
    const nextState = { viewportTop: maximumViewportTop, followBottom: true };
    historyViewportState.set(tui, nextState);
    return nextState;
  }

  const viewportTop = clamp(state.viewportTop, minimumViewportTop, maximumViewportTop);
  const followBottom = viewportTop >= maximumViewportTop;
  const nextState = { viewportTop, followBottom };
  historyViewportState.set(tui, nextState);
  return nextState;
}

function getInlineImageMoveUpRows(line: string): number {
  if (!isInlineImageProtocolLine(line)) {
    return 0;
  }

  let rows = 0;
  for (const match of line.matchAll(CURSOR_UP_ROWS_PATTERN)) {
    rows = Math.max(rows, Number.parseInt(match[1] ?? "0", 10));
  }

  return rows;
}

function countPrecedingBlankSpacerRows(lines: readonly string[], row: number, limit: number): number {
  let spacerRows = 0;

  while (spacerRows < limit) {
    const candidateRow = row - spacerRows - 1;
    if (candidateRow < 0 || (lines[candidateRow] ?? "") !== "") {
      break;
    }

    spacerRows += 1;
  }

  return spacerRows;
}

function isInlineImageProtocolLine(line: string): boolean {
  return INLINE_IMAGE_PROTOCOL_MARKERS.some((marker) => line.includes(marker));
}

function getInlineImageSpanEndingAt(lines: readonly string[], row: number): LineSpan | undefined {
  const line = lines[row] ?? "";
  if (!isInlineImageProtocolLine(line)) {
    return undefined;
  }

  const spacerRows = countPrecedingBlankSpacerRows(lines, row, getInlineImageMoveUpRows(line));
  return { start: row - spacerRows, endExclusive: row + 1 };
}

function collectInlineImageSpans(lines: readonly string[]): LineSpan[] {
  const spans: LineSpan[] = [];

  for (let row = 0; row < lines.length; row += 1) {
    const span = getInlineImageSpanEndingAt(lines, row);
    if (span) {
      spans.push(span);
    }
  }

  return spans;
}

function findContainingLineSpan(spans: readonly LineSpan[], row: number): LineSpan | undefined {
  return spans.find((span) => span.start <= row && row < span.endExclusive);
}

function lineSpanContentMatches(
  previousLines: readonly string[],
  previousSpan: LineSpan,
  nextLines: readonly string[],
  nextSpan: LineSpan,
): boolean {
  const previousSpanRows = previousSpan.endExclusive - previousSpan.start;
  const nextSpanRows = nextSpan.endExclusive - nextSpan.start;
  if (previousSpanRows !== nextSpanRows) {
    return false;
  }

  for (let offset = 0; offset < previousSpanRows; offset += 1) {
    if ((previousLines[previousSpan.start + offset] ?? "") !== (nextLines[nextSpan.start + offset] ?? "")) {
      return false;
    }
  }

  return true;
}

function alignViewportTopToInlineImageSpans(
  historyLines: readonly string[],
  viewportTop: number,
  historyRows: number,
): { viewportTop: number; unsupportedSpan?: LineSpan } {
  const maximumViewportTop = Math.max(0, historyLines.length - historyRows);
  const spans = collectInlineImageSpans(historyLines);
  let nextViewportTop = clamp(viewportTop, 0, maximumViewportTop);

  for (let iteration = 0; iteration <= spans.length; iteration += 1) {
    const viewportBottom = nextViewportTop + historyRows;
    const oversizedSpan = spans.find(
      (span) => span.endExclusive - span.start > historyRows
        && span.start < viewportBottom
        && nextViewportTop < span.endExclusive,
    );
    if (oversizedSpan) {
      return { viewportTop: nextViewportTop, unsupportedSpan: oversizedSpan };
    }

    const leadingSpan = spans.find((span) => span.start < nextViewportTop && nextViewportTop < span.endExclusive);
    if (leadingSpan) {
      nextViewportTop = leadingSpan.start;
      continue;
    }

    const trailingSpan = spans.find((span) => span.start < viewportBottom && viewportBottom < span.endExclusive);
    if (trailingSpan) {
      nextViewportTop = clamp(trailingSpan.endExclusive - historyRows, 0, maximumViewportTop);
      continue;
    }

    break;
  }

  return { viewportTop: nextViewportTop };
}

function createScreenLines(
  tui: object,
  historyLines: readonly string[],
  stickyLines: readonly string[],
  historyRows: number,
): { screenLines: string[]; historyViewportTop: number } | UnsupportedLayout {
  const { viewportTop, followBottom } = getHistoryViewportTop(tui, historyLines.length, historyRows);
  const alignedViewport = alignViewportTopToInlineImageSpans(historyLines, viewportTop, historyRows);
  if (alignedViewport.unsupportedSpan) {
    return {
      reason: "history-inline-image-span-too-tall",
      fields: {
        historyRows,
        viewportTop,
        spanStart: alignedViewport.unsupportedSpan.start,
        spanEndExclusive: alignedViewport.unsupportedSpan.endExclusive,
        spanRows: alignedViewport.unsupportedSpan.endExclusive - alignedViewport.unsupportedSpan.start,
      },
    };
  }

  const historyViewportTop = alignedViewport.viewportTop;
  const { maximumViewportTop } = getRetainedHistoryBounds(historyLines.length, historyRows);
  historyViewportState.set(tui, {
    viewportTop: historyViewportTop,
    followBottom: followBottom || historyViewportTop >= maximumViewportTop,
  });

  const visibleHistory = historyLines.slice(historyViewportTop, historyViewportTop + historyRows);
  const screenLines = [...visibleHistory];

  while (screenLines.length < historyRows) {
    screenLines.push("");
  }

  screenLines.push(...stickyLines);
  return { screenLines, historyViewportTop };
}

function normalizeVisibleLine(line: string, width: number): string {
  if (isInlineImageProtocolLine(line)) {
    return line;
  }

  return visibleWidth(line) > width ? truncateToWidth(line, width, "") : line;
}

function normalizeVisibleLines(lines: readonly string[], width: number): string[] {
  return lines.map((line) => normalizeVisibleLine(line, width));
}

export function highlightStickySplitFooterSelection(
  lines: readonly string[],
  start: { row: number; column: number },
  end: { row: number; column: number },
  historyRows: number,
): string[] {
  const first = start.row < end.row || (start.row === end.row && start.column <= end.column) ? start : end;
  const last = first === start ? end : start;
  const firstRow = clamp(first.row, 1, historyRows);
  const lastRow = clamp(last.row, 1, historyRows);

  return lines.map((line, index) => {
    const row = index + 1;
    if (row < firstRow || row > lastRow) return line;

    const plain = stripTerminalCodes(line);
    const startColumn = row === firstRow ? Math.max(1, first.column) : 1;
    const endColumn = row === lastRow ? Math.max(startColumn, last.column) : visibleWidth(plain);
    const startIndex = startColumn - 1;
    const length = endColumn - startColumn + 1;
    const selected = sliceByColumn(plain, startIndex, length);
    if (!selected) return line;

    return sliceByColumn(line, 0, startIndex)
      + `\x1b[7m${selected}\x1b[27m`
      + sliceByColumn(line, startIndex + visibleWidth(selected), Number.MAX_SAFE_INTEGER);
  });
}

function buildSplitLayout(tui: TuiWithInternals, width: number, height: number): SplitLayout | UnsupportedLayout {
  const footerStartIndex = findStickyPaneStartIndex(tui);
  if (footerStartIndex < 0) {
    return {
      reason: "unknown-layout",
      fields: {
        childCount: tui.children.length,
        expectedStickyPaneChildCount: STICKY_PANE_CHILD_COUNT,
      },
    };
  }

  const history = getRenderedHistory(tui, width, footerStartIndex);
  const sticky = renderChildren(tui.children.slice(footerStartIndex), width);
  const footerStartLine = history.lines.length;
  const stickyRows = sticky.lines.length;
  if (stickyRows <= 0) {
    return { reason: "empty-sticky-pane", fields: { footerStartIndex, footerStartLine } };
  }

  if (stickyRows >= height) {
    return { reason: "sticky-pane-too-tall", fields: { stickyRows, height } };
  }

  const historyRows = height - stickyRows;
  if (historyRows < options.minimumHistoryRows) {
    return {
      reason: "history-pane-too-small",
      fields: { historyRows, stickyRows, height, minimumHistoryRows: options.minimumHistoryRows },
    };
  }

  const screen = createScreenLines(tui, history.lines, sticky.lines, historyRows);
  if (isUnsupportedLayout(screen)) {
    return screen;
  }

  const { screenLines, historyViewportTop } = screen;

  return {
    logicalLineCount: footerStartLine + stickyRows,
    footerStartLine,
    stickyRows,
    historyRows,
    historyViewportTop,
    screenLines,
    historyTargets: history.targets,
  };
}

function isUnsupportedLayout(layout: object): layout is UnsupportedLayout {
  return "reason" in layout && typeof (layout as { reason?: unknown }).reason === "string";
}

function extractCursorPosition(lines: string[], height: number): CursorPosition | null {
  const viewportTop = Math.max(0, lines.length - height);
  for (let row = lines.length - 1; row >= viewportTop; row -= 1) {
    const line = lines[row] ?? "";
    const markerIndex = line.indexOf(CURSOR_MARKER);
    if (markerIndex === -1) {
      continue;
    }

    const beforeMarker = line.slice(0, markerIndex);
    const col = visibleWidth(beforeMarker);
    lines[row] = line.slice(0, markerIndex) + line.slice(markerIndex + CURSOR_MARKER.length);
    return { row, col };
  }

  return null;
}

function beginSynchronizedOutput(): string {
  return "\x1b[?2026h";
}

function endSynchronizedOutput(): string {
  return "\x1b[?2026l";
}

function clearViewportForStartupRedrawCompatibility(): string {
  return "\x1b[H\x1b[2J";
}

function moveTo(row: number, column: number): string {
  return `\x1b[${row};${column}H`;
}

function clearWholeLine(): string {
  return "\x1b[2K";
}

function clearToLineEnd(): string {
  return "\x1b[K";
}

function clearToLineEndIfNeeded(line: string, width: number): string {
  if (isInlineImageProtocolLine(line)) {
    return "";
  }

  return visibleWidth(line) < width ? clearToLineEnd() : "";
}

function logDiagnostic(event: string, fields: Record<string, unknown>): void {
  options.diagnostic?.(event, fields);
}

function rememberMetadata(tui: object, layout: SplitLayout): void {
  viewportMetadata.set(tui, {
    footerStartLine: layout.footerStartLine,
    stickyRows: layout.stickyRows,
    historyRows: layout.historyRows,
    historyViewportTop: layout.historyViewportTop,
    logicalLineCount: layout.logicalLineCount,
    historyTargets: layout.historyTargets,
  });
}

function createViewportStatus(tui: object, layout: SplitLayout): StickySplitFooterViewportStatus {
  const { minimumViewportTop, maximumViewportTop } = getRetainedHistoryBounds(layout.footerStartLine, layout.historyRows);
  const state = historyViewportState.get(tui);
  const followBottom = state?.followBottom ?? layout.historyViewportTop >= maximumViewportTop;

  return {
    active: true,
    atBottom: followBottom || layout.historyViewportTop >= maximumViewportTop,
    followBottom,
    viewportTop: layout.historyViewportTop,
    minimumViewportTop,
    maximumViewportTop,
    historyRows: layout.historyRows,
    historyLineCount: layout.footerStartLine,
  };
}

function getViewportStatusKey(status: StickySplitFooterViewportStatus | undefined): string {
  if (!status) {
    return "inactive";
  }

  return [
    status.active ? "active" : "inactive",
    status.atBottom ? "bottom" : "scrolled",
    status.followBottom ? "follow" : "pinned",
    status.viewportTop,
    status.minimumViewportTop,
    status.maximumViewportTop,
    status.historyRows,
    status.historyLineCount,
  ].join(":");
}

function notifyViewportStatus(tui: object, status: StickySplitFooterViewportStatus | undefined): void {
  const key = getViewportStatusKey(status);
  if (viewportStatusKeys.get(tui) === key) {
    return;
  }

  viewportStatusKeys.set(tui, key);
  options.onViewportStatusChange?.(status);
}

function updateRenderState(
  tui: TuiWithInternals,
  screenLines: string[],
  width: number,
  height: number,
  hardwareCursorRow?: number,
): void {
  tui.cursorRow = Math.max(0, screenLines.length - 1);
  if (hardwareCursorRow !== undefined) {
    tui.hardwareCursorRow = clamp(hardwareCursorRow, 0, Math.max(0, screenLines.length - 1));
  }
  tui.maxLinesRendered = Math.max(tui.maxLinesRendered, screenLines.length);
  tui.previousViewportTop = 0;
  tui.previousLines = screenLines;
  tui.previousWidth = width;
  tui.previousHeight = height;
}

function collectInlineImageSpanSets(
  previousLines: readonly string[],
  screenLines: readonly string[],
): { previousSpans: LineSpan[]; nextSpans: LineSpan[]; bothEmpty: boolean } {
  const previousSpans = collectInlineImageSpans(previousLines);
  const nextSpans = collectInlineImageSpans(screenLines);
  return { previousSpans, nextSpans, bothEmpty: previousSpans.length === 0 && nextSpans.length === 0 };
}

function expandRowsToRenderForInlineImageSpans(
  previousLines: readonly string[],
  screenLines: readonly string[],
  rowsToRender: readonly number[],
): number[] {
  if (rowsToRender.length === 0) {
    return [];
  }

  const { previousSpans, nextSpans, bothEmpty } = collectInlineImageSpanSets(previousLines, screenLines);
  if (bothEmpty) {
    return [...rowsToRender];
  }

  const expandedRows = new Set(rowsToRender);
  for (const row of rowsToRender) {
    for (const spans of [previousSpans, nextSpans]) {
      const span = findContainingLineSpan(spans, row);
      if (!span) {
        continue;
      }

      for (let spanRow = span.start; spanRow < span.endExclusive; spanRow += 1) {
        expandedRows.add(spanRow);
      }
    }
  }

  return [...expandedRows].sort((left, right) => left - right);
}

function getRowsToRender(
  previousLines: readonly string[],
  screenLines: readonly string[],
  forceFullRender: boolean,
): number[] {
  if (forceFullRender) {
    return screenLines.map((_line, index) => index);
  }

  const rows: number[] = [];
  const rowCount = Math.max(previousLines.length, screenLines.length);
  for (let row = 0; row < rowCount; row += 1) {
    if ((previousLines[row] ?? "") !== (screenLines[row] ?? "")) {
      rows.push(row);
    }
  }

  return expandRowsToRenderForInlineImageSpans(previousLines, screenLines, rows);
}

function renderBoundedViewport(
  tui: TuiWithInternals,
  layout: SplitLayout,
  cursorPos: CursorPosition | null,
  width: number,
  height: number,
  clear: boolean,
): void {
  tui.fullRedrawCount += clear ? 1 : 0;

  const rowsToRender = getRowsToRender(tui.previousLines, layout.screenLines, clear);
  let hardwareCursorRow = tui.hardwareCursorRow;

  if (rowsToRender.length > 0) {
    let buffer = beginSynchronizedOutput();
    if (clear) {
      buffer += `\x1b[r${clearViewportForStartupRedrawCompatibility()}`;
    }

    for (const screenRow of rowsToRender) {
      const line = layout.screenLines[screenRow] ?? "";
      buffer += clear
        ? `${moveTo(screenRow + 1, 1)}${clearWholeLine()}${line}`
        : `${moveTo(screenRow + 1, 1)}${line}${clearToLineEndIfNeeded(line, width)}`;
      hardwareCursorRow = screenRow;
    }

    buffer += endSynchronizedOutput();
    tui.terminal.write(buffer);
  }

  updateRenderState(tui, layout.screenLines, width, height, hardwareCursorRow);
  tui.positionHardwareCursor?.(cursorPos, layout.screenLines.length);
  rememberMetadata(tui, layout);
  notifyViewportStatus(tui as unknown as object, createViewportStatus(tui as unknown as object, layout));
}

function forceOriginalRenderer(
  tui: TuiWithInternals,
  originalDoRender: DoRender,
  thisArg: TUI,
  reason: string,
  fields: Record<string, unknown> = {},
): void {
  const leavingStickyRenderer = viewportMetadata.has(thisArg);
  viewportMetadata.delete(thisArg);
  toolsExpansionStates.delete(thisArg);
  renderedHistoryCaches.delete(thisArg);
  logDiagnostic("fallback", {
    reason,
    width: tui.terminal?.columns,
    height: tui.terminal?.rows,
    previousScreenRows: tui.previousLines.length,
    leavingStickyRenderer,
    ...fields,
  });

  if (leavingStickyRenderer) {
    notifyViewportStatus(thisArg as unknown as object, undefined);
    tui.previousLines = [];
    tui.previousWidth = -1;
    tui.previousHeight = -1;
    tui.cursorRow = 0;
    tui.hardwareCursorRow = 0;
    tui.previousViewportTop = 0;
  }

  originalDoRender.call(thisArg);
}

function handOffToOriginalRenderer(tui: TuiWithInternals, originalDoRender: DoRender, thisArg: TUI): void {
  if (viewportMetadata.has(thisArg)) {
    forceOriginalRenderer(tui, originalDoRender, thisArg, "sticky-renderer-disabled");
    return;
  }

  originalDoRender.call(thisArg);
}

function shouldForceFullClearForInlineImageSpans(
  previousLines: readonly string[],
  screenLines: readonly string[],
): boolean {
  const { previousSpans, nextSpans, bothEmpty } = collectInlineImageSpanSets(previousLines, screenLines);
  if (bothEmpty) {
    return false;
  }

  if (previousSpans.length !== nextSpans.length) {
    return true;
  }

  return previousSpans.some((span, index) => {
    const nextSpan = nextSpans[index];
    return !nextSpan
      || span.start !== nextSpan.start
      || span.endExclusive !== nextSpan.endExclusive
      || !lineSpanContentMatches(previousLines, span, screenLines, nextSpan);
  });
}

function shouldClearViewport(
  tui: TuiWithInternals,
  width: number,
  height: number,
  screenLines: readonly string[],
): boolean {
  return tui.previousLines.length === 0
    || tui.previousWidth !== width
    || tui.previousHeight !== height
    || !viewportMetadata.has(tui as unknown as object)
    || shouldForceFullClearForInlineImageSpans(tui.previousLines, screenLines);
}

function patchedDoRender(this: TUI): void {
  const tui = getTuiInternals(this);
  const prototype = Object.getPrototypeOf(this) as PatchedTuiPrototype | null;
  const originalDoRender = prototype?.__piStickyInputOriginalDoRender;

  if (!originalDoRender) {
    return;
  }

  if (!options.enabled || tui.stopped) {
    handOffToOriginalRenderer(tui, originalDoRender, this);
    return;
  }

  if (!hasRequiredInternals(tui)) {
    forceOriginalRenderer(tui, originalDoRender, this, "missing-required-tui-internals", {
      hasChildren: Array.isArray(tui.children),
      hasPreviousLines: Array.isArray(tui.previousLines),
      hasOverlayStack: Array.isArray(tui.overlayStack),
    });
    return;
  }

  const unsupportedTerminal = getUnsupportedTerminalReason(tui);
  if (unsupportedTerminal) {
    forceOriginalRenderer(tui, originalDoRender, this, unsupportedTerminal.reason, unsupportedTerminal.fields);
    return;
  }

  if (getVisibleOverlayState(tui)) {
    forceOriginalRenderer(tui, originalDoRender, this, "visible-overlay", {
      overlayCount: tui.overlayStack.length,
    });
    return;
  }

  const width = tui.terminal.columns;
  const height = tui.terminal.rows;
  let layout = buildSplitLayout(tui, width, height);

  if (isUnsupportedLayout(layout)) {
    forceOriginalRenderer(tui, originalDoRender, this, layout.reason, layout.fields);
    return;
  }

  const expanded = options.getToolsExpanded?.();
  if (expanded !== undefined) {
    const tuiKey = this as unknown as object;
    const state = toolsExpansionStates.get(tuiKey);
    const targets = getExpandableTargets(layout.historyTargets);
    const globalStateChanged = state?.expanded !== expanded;
    const targetsToSync = globalStateChanged
      ? targets
      : targets.filter((target) => !state.targets.has(target)
        || (!expanded && pendingStreamingComponents.has(target) && target.isPartial !== true));

    const nextState: ToolsExpansionState = globalStateChanged || !state
      ? { expanded, targets: new WeakSet<object>() }
      : state;
    for (const target of targets) nextState.targets.add(target);
    toolsExpansionStates.set(tuiKey, nextState);

    const toolsChanged = applyToolsExpanded(this, targetsToSync, expanded);
    if (toolsChanged || (state !== undefined && globalStateChanged)) {
      if (!refreshCachedComponents(tui, targetsToSync)) {
        const tailOnly = !globalStateChanged
          && targetsToSync.length === 1
          && isTailHistoryComponent(tui, targetsToSync[0]!);
        invalidateStickySplitFooterHistory(this, tailOnly ? "tail" : "all");
      }
      layout = buildSplitLayout(tui, width, height);
      if (isUnsupportedLayout(layout)) {
        forceOriginalRenderer(tui, originalDoRender, this, layout.reason, layout.fields);
        return;
      }
    }
  }

  const cursorPos = extractCursorPosition(layout.screenLines, height);
  const appliedLines = tui.applyLineResets?.(layout.screenLines) ?? layout.screenLines;
  const normalizedLines = normalizeVisibleLines(appliedLines, width);
  const selection = transcriptSelections.get(this as unknown as object);
  const appliedLayout: SplitLayout = {
    ...layout,
    screenLines: selection
      ? highlightStickySplitFooterSelection(normalizedLines, selection.start, selection.end, layout.historyRows)
      : normalizedLines,
  };

  renderBoundedViewport(
    tui,
    appliedLayout,
    cursorPos,
    width,
    height,
    shouldClearViewport(tui, width, height, appliedLayout.screenLines),
  );
}

export function invalidateStickySplitFooterHistory(
  runtimeTui?: TUI,
  mode: "all" | "tail" | "message" = "all",
): void {
  if (runtimeTui) {
    const tuiKey = runtimeTui as unknown as object;
    const cached = renderedHistoryCaches.get(tuiKey);
    if (mode !== "all" && cached) {
      const target = mode === "tail"
        ? cached.tailComponent
        : getLastAssistantMessageComponent(cached.rootChildren);
      if (target) cached.dirtyComponents.add(target);
      else renderedHistoryCaches.delete(tuiKey);
    } else {
      renderedHistoryCaches.delete(tuiKey);
    }
  } else {
    renderedHistoryCaches = new WeakMap<object, RenderedHistoryCache>();
    renderedComponentLineCounts = new WeakMap<object, number>();
  }
}

export function configureStickySplitFooterRenderer(nextOptions: StickySplitFooterRendererOptions): void {
  const viewportStatusListenerChanged = options.onViewportStatusChange !== nextOptions.onViewportStatusChange;
  const toolsExpandedGetterChanged = options.getToolsExpanded !== nextOptions.getToolsExpanded;

  options = {
    enabled: nextOptions.enabled,
    minimumHistoryRows: Math.max(1, Math.floor(nextOptions.minimumHistoryRows)),
    historyViewportLineLimit: Math.max(
      Math.max(1, Math.floor(nextOptions.minimumHistoryRows)),
      Math.floor(nextOptions.historyViewportLineLimit),
    ),
    diagnostic: nextOptions.diagnostic,
    onViewportStatusChange: nextOptions.onViewportStatusChange,
    formatMuted: nextOptions.formatMuted,
    getToolsExpanded: nextOptions.getToolsExpanded,
  };

  if (viewportStatusListenerChanged) {
    viewportStatusKeys = new WeakMap<object, string>();
  }
  if (toolsExpandedGetterChanged) {
    toolsExpansionStates = new WeakMap<object, ToolsExpansionState>();
  }
  invalidateStickySplitFooterHistory();
}

function resolveRuntimeTuiPrototype(runtimeTui: TUI | undefined): PatchedTuiPrototype | undefined {
  if (!runtimeTui || typeof runtimeTui !== "object") {
    return undefined;
  }

  const prototype = Object.getPrototypeOf(runtimeTui) as PatchedTuiPrototype | null;
  if (!prototype || typeof prototype !== "object") {
    return undefined;
  }

  return prototype;
}

export function applyStickySplitFooterRendererPatch(
  nextOptions: StickySplitFooterRendererOptions,
  runtimeTui?: TUI,
): StickySplitFooterPatchStatus {
  configureStickySplitFooterRenderer(nextOptions);

  const prototype = resolveRuntimeTuiPrototype(runtimeTui);
  if (!prototype) {
    lastPatchReason = "awaiting-runtime-tui-instance";
    return { installed: patchInstalled, active: patchInstalled && options.enabled, reason: lastPatchReason };
  }

  if (prototype.__piStickyInputPatched) {
    if (typeof prototype.__piStickyInputOriginalDoRender !== "function") {
      patchInstalled = false;
      lastPatchReason = "missing-original-doRender";
      return { installed: false, active: false, reason: lastPatchReason };
    }

    prototype.doRender = patchedDoRender;
    patchInstalled = true;
    lastPatchReason = "already-installed";
    return { installed: true, active: options.enabled, reason: lastPatchReason };
  }

  if (typeof prototype.doRender !== "function") {
    patchInstalled = false;
    lastPatchReason = "missing-runtime-TUI.prototype.doRender";
    return { installed: false, active: false, reason: lastPatchReason };
  }

  prototype.__piStickyInputOriginalDoRender = prototype.doRender;
  prototype.doRender = patchedDoRender;
  prototype.__piStickyInputPatched = true;
  patchInstalled = true;
  lastPatchReason = "installed";

  return { installed: true, active: options.enabled, reason: lastPatchReason };
}

function getCurrentViewportTop(
  tui: object,
  historyLineCount: number,
  historyRows: number,
): { currentViewportTop: number; minimumViewportTop: number; maximumViewportTop: number } {
  const { minimumViewportTop, maximumViewportTop } = getRetainedHistoryBounds(historyLineCount, historyRows);
  const currentState = historyViewportState.get(tui);
  const currentViewportTop = currentState?.followBottom === false
    ? currentState.viewportTop
    : maximumViewportTop;

  return { currentViewportTop, minimumViewportTop, maximumViewportTop };
}

function updateViewportTop(
  runtimeTui: TUI,
  tui: object,
  currentViewportTop: number,
  viewportTop: number,
  minimumViewportTop: number,
  maximumViewportTop: number,
  historyRows: number,
  historyLineCount: number,
): StickySplitFooterScrollResult {
  const currentState = historyViewportState.get(tui);
  const followBottom = viewportTop >= maximumViewportTop;
  const changed = viewportTop !== currentViewportTop || currentState?.followBottom !== followBottom;

  followBottomOnNextAppend.delete(tui);
  historyViewportState.set(tui, { viewportTop, followBottom });
  notifyViewportStatus(tui, {
    active: true,
    atBottom: followBottom,
    followBottom,
    viewportTop,
    minimumViewportTop,
    maximumViewportTop,
    historyRows,
    historyLineCount,
  });

  if (changed) {
    runtimeTui.requestRender();
  }

  return { handled: true, changed, viewportTop, followBottom };
}

export function scrollStickySplitFooterViewport(
  runtimeTui: TUI | undefined,
  deltaRows: number,
): StickySplitFooterScrollResult {
  if (!runtimeTui || !Number.isFinite(deltaRows) || deltaRows === 0) {
    return { handled: false, changed: false };
  }

  const tui = runtimeTui as unknown as object;
  const metadata = viewportMetadata.get(tui);
  if (!metadata) {
    return { handled: false, changed: false };
  }

  const { currentViewportTop, minimumViewportTop, maximumViewportTop } = getCurrentViewportTop(
    tui,
    metadata.footerStartLine,
    metadata.historyRows,
  );
  const viewportTop = clamp(currentViewportTop + Math.trunc(deltaRows), minimumViewportTop, maximumViewportTop);

  return updateViewportTop(
    runtimeTui,
    tui,
    currentViewportTop,
    viewportTop,
    minimumViewportTop,
    maximumViewportTop,
    metadata.historyRows,
    metadata.footerStartLine,
  );
}

function stripTerminalCodes(line: string): string {
  return line
    .replace(/\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)/g, "")
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(CURSOR_MARKER, "");
}

export function isStickySplitFooterTextAt(
  runtimeTui: TUI | undefined,
  row: number,
  column: number,
  text: string,
): boolean {
  if (!runtimeTui || row < 1 || column < 1 || !text) return false;
  const line = getTuiInternals(runtimeTui).previousLines[row - 1];
  if (line === undefined) return false;

  const plain = stripTerminalCodes(line);
  const index = plain.indexOf(text);
  if (index < 0) return false;
  const startColumn = visibleWidth(plain.slice(0, index)) + 1;
  return column >= startColumn && column < startColumn + visibleWidth(text);
}

function getPointText(line: string, startColumn: number, endColumn?: number): string {
  const start = Math.max(0, startColumn - 1);
  return sliceByColumn(stripTerminalCodes(line), start, endColumn === undefined ? Number.MAX_SAFE_INTEGER : Math.max(0, endColumn - startColumn + 1));
}

export function setStickySplitFooterSelection(
  runtimeTui: TUI | undefined,
  start?: { row: number; column: number },
  end?: { row: number; column: number },
): boolean {
  if (!runtimeTui) return false;
  const tui = runtimeTui as unknown as object;
  const metadata = viewportMetadata.get(tui);

  if (!start || !end) {
    const changed = transcriptSelections.delete(tui);
    if (changed) runtimeTui.requestRender();
    return changed;
  }

  if (!metadata || start.row < 1 || start.row > metadata.historyRows) return false;
  transcriptSelections.set(tui, {
    start,
    end: { ...end, row: clamp(end.row, 1, metadata.historyRows) },
  });
  runtimeTui.requestRender();
  return true;
}

export function getStickySplitFooterSelectionText(
  runtimeTui: TUI | undefined,
  start: { row: number; column: number },
  end: { row: number; column: number },
): string | undefined {
  if (!runtimeTui) return undefined;
  const tui = runtimeTui as unknown as object;
  const metadata = viewportMetadata.get(tui);
  const internals = getTuiInternals(runtimeTui);
  if (!metadata || start.row < 1 || start.row > metadata.historyRows) return undefined;

  const boundedEnd = { ...end, row: clamp(end.row, 1, metadata.historyRows) };
  const first = start.row < boundedEnd.row || (start.row === boundedEnd.row && start.column <= boundedEnd.column)
    ? start
    : boundedEnd;
  const last = first === start ? boundedEnd : start;
  const lines = internals.previousLines.slice(first.row - 1, last.row);
  if (lines.length === 0) return undefined;

  return lines.map((line, index) => {
    if (lines.length === 1) return getPointText(line, first.column, last.column);
    if (index === 0) return getPointText(line, first.column);
    if (index === lines.length - 1) return getPointText(line, 1, last.column);
    return stripTerminalCodes(line);
  }).join("\n");
}

function getComponentExpanded(target: ExpandableComponent): boolean {
  return typeof target.expanded === "boolean"
    ? target.expanded
    : typeof target._expanded === "boolean"
      ? target._expanded
      : false;
}

function getComponentToggleStrategy(
  target: ExpandableComponent,
  width: number,
): "native" | "compact" {
  let strategy = componentToggleStrategies.get(target);
  if (strategy) return strategy;

  const expanded = getComponentExpanded(target);
  target.setExpanded(false);
  const collapsedRows = target.render(width).length;
  target.setExpanded(true);
  const expandedRows = target.render(width).length;
  target.setExpanded(expanded);
  strategy = expandedRows > FORCED_COLLAPSED_ROW_LIMIT
    && (collapsedRows === expandedRows || collapsedRows < FORCED_COLLAPSED_ROW_LIMIT)
    ? "compact"
    : "native";
  componentToggleStrategies.set(target, strategy);
  return strategy;
}

function getExpandableTargets(
  historyTargets: readonly (ExpandableComponent | undefined)[],
): ExpandableComponent[] {
  return [...new Set(historyTargets.filter((target): target is ExpandableComponent => target !== undefined))];
}

function applyToolsExpanded(
  runtimeTui: TUI,
  historyTargets: readonly (ExpandableComponent | undefined)[],
  expanded: boolean,
): boolean {
  let changed = false;
  const targets = getExpandableTargets(historyTargets);
  for (const target of targets) {
    locallyToggledComponents.delete(target);
    const wasExpanded = getComponentExpanded(target);

    if (expanded) {
      pendingStreamingComponents.delete(target);
      changed = compactedComponents.delete(target) || changed;
    } else if (target.isPartial === true) {
      pendingStreamingComponents.add(target);
    } else {
      pendingStreamingComponents.delete(target);
      const strategy = getComponentToggleStrategy(target, runtimeTui.terminal.columns);
      if (strategy === "compact" && !compactedComponents.has(target)) {
        compactedComponents.add(target);
        changed = true;
      }
    }

    if (wasExpanded !== expanded) target.setExpanded(expanded);
    changed = wasExpanded !== expanded || changed;
  }

  return changed;
}

export function setStickySplitFooterToolsExpanded(
  runtimeTui: TUI | undefined,
  expanded: boolean,
): boolean {
  if (!runtimeTui) return false;
  const tui = runtimeTui as unknown as object;
  const metadata = viewportMetadata.get(tui);
  if (!metadata) return false;

  const targets = getExpandableTargets(metadata.historyTargets);
  applyToolsExpanded(runtimeTui, targets, expanded);
  toolsExpansionStates.set(tui, {
    expanded,
    targets: new WeakSet(targets),
  });
  if (!refreshCachedComponents(getTuiInternals(runtimeTui), targets)) {
    invalidateStickySplitFooterHistory(runtimeTui);
  }
  runtimeTui.requestRender();
  return true;
}

export function setStickySplitFooterToolsExpandedIncrementally(
  runtimeTui: TUI | undefined,
  expanded: boolean,
  batchSize = 2,
): boolean {
  if (!runtimeTui) return false;
  const tui = runtimeTui as unknown as object;
  const metadata = viewportMetadata.get(tui);
  if (!metadata) return false;

  const targets = getExpandableTargets(metadata.historyTargets);
  const generation = (toolsExpansionGenerations.get(tui) ?? 0) + 1;
  toolsExpansionGenerations.set(tui, generation);
  toolsExpansionStates.set(tui, {
    expanded,
    targets: new WeakSet(targets),
  });

  let index = 0;
  const applyNextBatch = () => {
    if (toolsExpansionGenerations.get(tui) !== generation) return;
    const batch = targets.slice(index, index + Math.max(1, batchSize));
    index += batch.length;
    applyToolsExpanded(runtimeTui, batch, expanded);

    if (!refreshCachedComponents(getTuiInternals(runtimeTui), batch)) {
      applyToolsExpanded(runtimeTui, targets.slice(index), expanded);
      invalidateStickySplitFooterHistory(runtimeTui);
      runtimeTui.requestRender();
      return;
    }

    runtimeTui.requestRender();
    if (index < targets.length) setTimeout(applyNextBatch, 0);
  };

  setTimeout(applyNextBatch, 0);
  return true;
}

export function toggleStickySplitFooterComponentAt(
  runtimeTui: TUI | undefined,
  row: number,
): boolean {
  if (!runtimeTui) return false;
  const tui = runtimeTui as unknown as object;
  const metadata = viewportMetadata.get(tui);
  if (!metadata || row < 1 || row > metadata.historyRows) return false;

  const target = metadata.historyTargets[metadata.historyViewportTop + row - 1];
  if (!target) return false;

  const expanded = getComponentExpanded(target);
  const strategy = getComponentToggleStrategy(target, runtimeTui.terminal.columns);
  pendingStreamingComponents.delete(target);
  locallyToggledComponents.add(target);

  if (strategy === "compact") {
    if (compactedComponents.has(target)) {
      compactedComponents.delete(target);
      target.setExpanded(true);
    } else {
      compactedComponents.add(target);
      target.setExpanded(false);
      const targetStart = metadata.historyTargets.indexOf(target);
      const viewportState = historyViewportState.get(tui);
      if (targetStart >= 0 && viewportState && targetStart < viewportState.viewportTop) {
        historyViewportState.set(tui, { viewportTop: targetStart, followBottom: false });
        followBottomOnNextAppend.add(tui);
      }
    }
  } else {
    target.setExpanded(!expanded);
  }
  if (!refreshCachedComponents(getTuiInternals(runtimeTui), [target])) {
    invalidateStickySplitFooterHistory(runtimeTui);
  }
  runtimeTui.requestRender();
  return true;
}

export function resetStickySplitFooterViewport(runtimeTui?: TUI): void {
  if (!runtimeTui) {
    return;
  }

  const tui = runtimeTui as unknown as object;
  notifyViewportStatus(tui, undefined);
  historyViewportState.delete(tui);
  followBottomOnNextAppend.delete(tui);
  toolsExpansionGenerations.set(tui, (toolsExpansionGenerations.get(tui) ?? 0) + 1);
  viewportMetadata.delete(tui);
  transcriptSelections.delete(tui);
  toolsExpansionStates.delete(tui);
  renderedHistoryCaches.delete(tui);
}

export function getStickySplitFooterPatchStatus(): StickySplitFooterPatchStatus {
  return {
    installed: patchInstalled,
    active: patchInstalled && options.enabled,
    reason: lastPatchReason,
  };
}
