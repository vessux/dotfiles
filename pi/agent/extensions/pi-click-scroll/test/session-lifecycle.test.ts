import assert from "node:assert/strict";
import test from "node:test";

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Container, Text, type Component, type TUI } from "@earendil-works/pi-tui";
import stickyInputExtension from "../src/index.ts";
import { toggleStickySplitFooterComponentAt } from "../src/tui/split-footer-renderer.ts";

class FixedSizeExpandable implements Component {
  expanded = false;

  render(): string[] {
    return ["", "tool", ...Array.from({ length: 8 }, (_, index) => `  detail-${index}`)];
  }

  setExpanded(expanded: boolean): void {
    this.expanded = expanded;
  }

  invalidate(): void {}
}

class FakeTui {
  children: Component[];
  terminal = { columns: 80, rows: 30, write: (_data: string) => {} };
  previousLines: string[] = [];
  previousWidth = -1;
  previousHeight = -1;
  cursorRow = 0;
  hardwareCursorRow = 0;
  clearOnShrink = true;
  maxLinesRendered = 0;
  previousViewportTop = 0;
  fullRedrawCount = 0;
  stopped = false;
  overlayStack: unknown[] = [];

  constructor(block: Component) {
    const history = new Container();
    history.addChild(block);
    this.children = [history, ...Array.from({ length: 5 }, () => new Text("sticky", 0, 0))];
  }

  doRender(): void {}
  extractCursorPosition(): null { return null; }
  applyLineResets(lines: string[]): string[] { return lines; }
  positionHardwareCursor(): void {}
  requestRender(): void { this.doRender(); }
  stop(): void {}
}

test("renderer does not retain a stale session context after shutdown", async () => {
  const handlers = new Map<string, (event: unknown, ctx: ExtensionContext) => unknown>();
  const pi = {
    on: (event: string, handler: (event: unknown, ctx: ExtensionContext) => unknown) => handlers.set(event, handler),
    registerCommand: () => {},
  } as unknown as ExtensionAPI;
  stickyInputExtension(pi);

  let active = true;
  let toolsExpanded = false;
  let widgetFactory: ((tui: TUI) => Component) | undefined;
  let terminalInput: ((data: string) => unknown) | undefined;
  const statuses = new Map<string, string | undefined>();
  const ui = {
    theme: { fg: (_color: string, text: string) => text },
    notify: () => {},
    setStatus: (key: string, text: string | undefined) => { statuses.set(key, text); },
    setWidget: (_key: string, factory: ((tui: TUI) => Component) | undefined) => { widgetFactory = factory; },
    onTerminalInput: (handler: (data: string) => unknown) => {
      terminalInput = handler;
      return () => { terminalInput = undefined; };
    },
    getEditorText: () => "",
    getToolsExpanded: () => toolsExpanded,
  };
  const ctx = {
    cwd: process.cwd(),
    hasUI: true,
    get ui() {
      if (!active) throw new Error("stale session ctx");
      return ui;
    },
  } as unknown as ExtensionContext;

  await handlers.get("session_start")?.({}, ctx);
  assert.ok(widgetFactory);

  const block = new FixedSizeExpandable();
  const tui = new FakeTui(block);
  widgetFactory(tui as unknown as TUI);
  tui.doRender();
  await Promise.resolve();
  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 2), true);
  assert.match(statuses.get("pi-click-scroll:tools-status") ?? "", /tools collapsed .* expand/);

  const ctrlO = terminalInput?.("\x0f") as { consume?: boolean } | undefined;
  assert.equal(ctrlO?.consume, true);
  await new Promise((resolve) => setTimeout(resolve, 10));
  assert.equal(block.expanded, true);
  assert.match(statuses.get("pi-click-scroll:tools-status") ?? "", /tools expanded .* collapse/);

  await handlers.get("session_shutdown")?.({ reason: "reload" }, ctx);
  active = false;

  assert.doesNotThrow(() => tui.doRender());
});
