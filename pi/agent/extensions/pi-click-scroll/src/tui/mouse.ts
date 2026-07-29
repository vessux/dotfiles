export type MouseWheelDirection = "up" | "down";

export interface StickyMouseEvent {
  kind: "press" | "release" | "drag" | "wheel";
  button: number;
  column: number;
  row: number;
  direction?: MouseWheelDirection;
}

export interface StickyMousePoint {
  row: number;
  column: number;
}

export interface StickyMouseSelection {
  start?: StickyMousePoint;
  end?: StickyMousePoint;
  dragged?: boolean;
}

export type StickyMouseSelectionAction =
  | "start"
  | { type: "drag" | "copy"; start: StickyMousePoint; end: StickyMousePoint }
  | { type: "click"; point: StickyMousePoint };

const SGR_MOUSE_PATTERN = /\x1b\[<(\d+);(\d+);(\d+)([mM])/g;
const MOUSE_MODIFIER_MASK = 4 | 8 | 16;
const MOUSE_DRAG_MASK = 32;
const WHEEL_UP_BUTTON = 64;
const WHEEL_DOWN_BUTTON = 65;

export function getMouseWheelDirection(rawButton: number): MouseWheelDirection | undefined {
  const button = rawButton & ~(MOUSE_MODIFIER_MASK | MOUSE_DRAG_MASK);
  if (button === WHEEL_UP_BUTTON) return "up";
  if (button === WHEEL_DOWN_BUTTON) return "down";
  return undefined;
}

export function parseStickyMouseEvents(data: string): StickyMouseEvent[] {
  SGR_MOUSE_PATTERN.lastIndex = 0;
  const events: StickyMouseEvent[] = [];
  for (const match of data.matchAll(SGR_MOUSE_PATTERN)) {
    const rawButton = Number.parseInt(match[1] ?? "", 10);
    const column = Number.parseInt(match[2] ?? "", 10);
    const row = Number.parseInt(match[3] ?? "", 10);
    const suffix = match[4];
    if (!Number.isFinite(rawButton) || !Number.isFinite(column) || !Number.isFinite(row)) continue;

    const direction = getMouseWheelDirection(rawButton);
    events.push({
      kind: direction ? "wheel" : suffix === "m" ? "release" : (rawButton & MOUSE_DRAG_MASK) !== 0 ? "drag" : "press",
      button: rawButton & ~(MOUSE_MODIFIER_MASK | MOUSE_DRAG_MASK),
      column,
      row,
      direction,
    });
  }
  return events;
}

export function parseStickyMouseEvent(data: string): StickyMouseEvent | undefined {
  return parseStickyMouseEvents(data).at(-1);
}

export function advanceStickyMouseSelection(
  selection: StickyMouseSelection,
  event: StickyMouseEvent,
): StickyMouseSelectionAction | undefined {
  const point = { row: event.row, column: event.column };

  if (event.kind === "press" && event.button === 0) {
    selection.start = point;
    selection.end = point;
    selection.dragged = false;
    return "start";
  }

  if (event.kind === "drag" && event.button === 0 && selection.start) {
    selection.end = point;
    selection.dragged = true;
    return { type: "drag", start: selection.start, end: point };
  }

  if (event.kind === "release" && selection.start) {
    const start = selection.start;
    const dragged = selection.dragged === true;
    selection.start = undefined;
    selection.end = undefined;
    selection.dragged = false;
    return dragged
      ? { type: "copy", start, end: point }
      : { type: "click", point: start };
  }

  return undefined;
}

export function isSgrMouseInput(data: string): boolean {
  SGR_MOUSE_PATTERN.lastIndex = 0;
  return SGR_MOUSE_PATTERN.test(data);
}
