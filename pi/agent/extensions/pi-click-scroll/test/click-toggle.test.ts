import assert from "node:assert/strict";
import test from "node:test";

import { Container, Text, visibleWidth, type Component, type TUI } from "@earendil-works/pi-tui";
import {
  applyStickySplitFooterRendererPatch,
  invalidateStickySplitFooterHistory,
  isStickySplitFooterTextAt,
  scrollStickySplitFooterViewport,
  setStickySplitFooterToolsExpanded,
  setStickySplitFooterToolsExpandedIncrementally,
  toggleStickySplitFooterComponentAt,
} from "../src/tui/split-footer-renderer.ts";

class FixedSizeExpandable implements Component {
  expanded = false;

  render(): string[] {
    return [
      "",
      "tool",
      ...Array.from(
        { length: 8 },
        (_, index) => `\x1b[42m${`  detail-${index}`.padEnd(80)}\x1b[0m`,
      ),
    ];
  }

  setExpanded(expanded: boolean): void {
    this.expanded = expanded;
  }

  invalidate(): void {}
}

class ResizingExpandable extends FixedSizeExpandable {
  override render(): string[] {
    return this.expanded
      ? super.render()
      : ["", "tool", "summary", "", "", ""];
  }
}

class OneLineCollapsedExpandable extends FixedSizeExpandable {
  override render(): string[] {
    return this.expanded ? super.render() : ["tool"];
  }
}

class CountingHistoryComponent implements Component {
  renderCalls = 0;

  render(): string[] {
    this.renderCalls += 1;
    return ["history"];
  }

  invalidate(): void {}
}

class MutableHistoryComponent extends CountingHistoryComponent {
  text = "before";

  override render(): string[] {
    this.renderCalls += 1;
    return [this.text];
  }
}

class InitiallyEmptyHistoryComponent extends CountingHistoryComponent {
  text = "";

  override render(): string[] {
    this.renderCalls += 1;
    return this.text ? [this.text] : [];
  }
}

class AssistantMessageComponent extends InitiallyEmptyHistoryComponent {}

class CountingShortExpandable implements Component {
  expanded = false;
  setExpandedCalls = 0;

  render(): string[] {
    return ["tool"];
  }

  setExpanded(expanded: boolean): void {
    this.setExpandedCalls += 1;
    this.expanded = expanded;
  }

  invalidate(): void {}
}

class GrowingFixedSizeExpandable extends FixedSizeExpandable {
  complete = false;
  isPartial = true;

  override render(): string[] {
    return this.complete ? super.render() : ["tool"];
  }
}

class BashExecutionComponent extends CountingHistoryComponent {
  status = "running";

  override render(): string[] {
    this.renderCalls += 1;
    return [this.status === "running" ? "Running..." : "done"];
  }
}

class LongFixedSizeExpandable extends FixedSizeExpandable {
  override render(): string[] {
    return [
      "",
      "tool",
      ...Array.from(
        { length: 80 },
        (_, index) => `\x1b[42m${`  detail-${index}`.padEnd(80)}\x1b[0m`,
      ),
    ];
  }
}

class FakeTui {
  children: Component[] = [];
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

  doRender(): void {}
  extractCursorPosition(): null { return null; }
  applyLineResets(lines: string[]): string[] { return lines; }
  positionHardwareCursor(): void {}
  requestRender(): void { this.doRender(); }
}

function createTui(block: Component, trailingRows = 0, getToolsExpanded?: () => boolean): FakeTui {
  const history = new Container();
  history.addChild(block);
  if (trailingRows > 0) {
    history.addChild(new Text(Array.from({ length: trailingRows }, (_, index) => `after-${index}`).join("\n"), 0, 0));
  }

  const tui = new FakeTui();
  const sticky = Array.from({ length: 5 }, () => {
    const child = new Container();
    child.addChild(new Text("sticky", 0, 0));
    return child;
  });
  tui.children = [history, ...sticky];

  applyStickySplitFooterRendererPatch({
    enabled: true,
    minimumHistoryRows: 3,
    historyViewportLineLimit: 200,
    formatMuted: (text) => `\x1b[90m${text}\x1b[39m`,
    getToolsExpanded,
  }, tui as unknown as TUI);
  tui.doRender();
  return tui;
}

test("clickable scroll status matches only its visible text columns", () => {
  const tui = createTui(new CountingHistoryComponent());
  tui.previousLines[0] = "  \x1b[90m↓ Jump to bottom\x1b[39m  tools collapsed";

  assert.equal(isStickySplitFooterTextAt(tui as unknown as TUI, 1, 3, "↓ Jump to bottom"), true);
  assert.equal(isStickySplitFooterTextAt(tui as unknown as TUI, 1, 2, "↓ Jump to bottom"), false);
  assert.equal(isStickySplitFooterTextAt(tui as unknown as TUI, 1, 19, "↓ Jump to bottom"), false);
});

test("click uses compact/full states when native expansion does not resize a large component", () => {
  const block = new FixedSizeExpandable();
  const tui = createTui(block);

  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 2), true);
  assert.equal(block.expanded, false);
  const hintIndex = tui.previousLines.findIndex((line) => line.includes("... (6 more lines)"));
  assert.ok(hintIndex >= 0);
  assert.ok(tui.previousLines[hintIndex]?.includes("\x1b[42m"));
  assert.ok(tui.previousLines[hintIndex]?.includes("\x1b[90m... (6 more lines)\x1b[39m"));
  assert.equal(visibleWidth(tui.previousLines[hintIndex] ?? ""), 80);
  const emptyLine = tui.previousLines[hintIndex + 1] ?? "";
  assert.ok(emptyLine.includes("\x1b[42m"));
  assert.equal(emptyLine.replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "").trim(), "");

  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 2), true);
  assert.equal(block.expanded, true);
  assert.ok(tui.previousLines.some((line) => line.includes("detail-7")));
  assert.ok(tui.previousLines.every((line) => !line.includes("more lines")));
});

test("compacting a block whose top is off-screen scrolls its hint into view", () => {
  const tui = createTui(new LongFixedSizeExpandable(), 100);
  scrollStickySplitFooterViewport(tui as unknown as TUI, -Number.MAX_SAFE_INTEGER);
  scrollStickySplitFooterViewport(tui as unknown as TUI, 30);

  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 2), true);
  assert.ok(tui.previousLines.some((line) => line.includes("more lines")));
});

test("new history resumes bottom-following after an off-screen block is compacted", () => {
  const tui = createTui(new LongFixedSizeExpandable(), 100);
  const history = tui.children[0] as Container;
  scrollStickySplitFooterViewport(tui as unknown as TUI, -Number.MAX_SAFE_INTEGER);
  scrollStickySplitFooterViewport(tui as unknown as TUI, 30);
  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 2), true);

  history.addChild(new Text("new-tail", 0, 0));
  tui.doRender();

  assert.ok(tui.previousLines.some((line) => line.includes("new-tail")));
});

test("one-line native collapse uses the four-row preview and hint", () => {
  const tui = createTui(new OneLineCollapsedExpandable(), 0, () => false);

  assert.ok(tui.previousLines.some((line) => line.includes("detail-1")));
  assert.ok(tui.previousLines.some((line) => line.includes("more lines")));
});

test("unchanged history is reused across typing and scroll redraws", () => {
  const block = new CountingHistoryComponent();
  const tui = createTui(block);
  const initialRenderCalls = block.renderCalls;

  for (let redraw = 0; redraw < 5; redraw += 1) tui.doRender();

  assert.equal(block.renderCalls, initialRenderCalls);
});

test("appending history renders only the new tail component", () => {
  const earlier = new CountingHistoryComponent();
  const tui = createTui(earlier);
  const history = tui.children[0] as Container;
  const appended = new CountingHistoryComponent();
  const earlierRenderCalls = earlier.renderCalls;

  history.addChild(appended);
  tui.doRender();

  assert.equal(earlier.renderCalls, earlierRenderCalls);
  assert.equal(appended.renderCalls, 1);
});

test("appending chat history skips a trailing empty pending-message container", () => {
  const earlier = new CountingHistoryComponent();
  const tui = createTui(earlier);
  const history = tui.children[0] as Container;
  tui.children.splice(0, 1, new Container(), new Container(), history, new Container());
  invalidateStickySplitFooterHistory(tui as unknown as TUI);
  tui.doRender();
  const earlierRenderCalls = earlier.renderCalls;

  history.addChild(new CountingHistoryComponent());
  tui.doRender();

  assert.equal(earlier.renderCalls, earlierRenderCalls);
});

test("streaming updates replace only the cached tail component", () => {
  const earlier = new CountingHistoryComponent();
  const tui = createTui(earlier);
  const history = tui.children[0] as Container;
  const tail = new MutableHistoryComponent();
  history.addChild(tail);
  tui.doRender();
  const earlierRenderCalls = earlier.renderCalls;
  const tailRenderCalls = tail.renderCalls;

  tail.text = "after";
  invalidateStickySplitFooterHistory(tui as unknown as TUI, "tail");
  tui.doRender();

  assert.equal(earlier.renderCalls, earlierRenderCalls);
  assert.equal(tail.renderCalls, tailRenderCalls + 1);
  assert.ok(tui.previousLines.some((line) => line.includes("after")));
});

test("streaming content appears after its component was appended empty", () => {
  const earlier = new CountingHistoryComponent();
  const tui = createTui(earlier);
  const history = tui.children[0] as Container;
  const tail = new InitiallyEmptyHistoryComponent();
  history.addChild(tail);
  tui.doRender();
  const earlierRenderCalls = earlier.renderCalls;

  tail.text = "streamed";
  invalidateStickySplitFooterHistory(tui as unknown as TUI, "tail");
  tui.doRender();

  assert.equal(earlier.renderCalls, earlierRenderCalls);
  assert.ok(tui.previousLines.some((line) => line.includes("streamed")));
});

test("assistant text streamed after a collapsed tool result is visible", () => {
  const assistant = new AssistantMessageComponent();
  const tui = createTui(assistant, 0, () => false);
  const history = tui.children[0] as Container;
  history.addChild(new FixedSizeExpandable());
  tui.doRender();

  assistant.text = "final reply";
  invalidateStickySplitFooterHistory(tui as unknown as TUI, "message");
  tui.doRender();

  assert.ok(tui.previousLines.some((line) => line.includes("final reply")));
});

test("a running user-bash component is refreshed when it completes", () => {
  const block = new BashExecutionComponent();
  const tui = createTui(block);
  const renderCalls = block.renderCalls;

  block.status = "complete";
  tui.doRender();

  assert.equal(block.renderCalls, renderCalls + 1);
  assert.ok(tui.previousLines.some((line) => line.includes("done")));
});

test("stable short blocks are classified only once across redraws", () => {
  const block = new CountingShortExpandable();
  const tui = createTui(block, 0, () => false);
  const initialSetExpandedCalls = block.setExpandedCalls;

  for (let redraw = 0; redraw < 5; redraw += 1) tui.doRender();

  assert.equal(block.setExpandedCalls, initialSetExpandedCalls);
});

test("new compact-strategy blocks inherit an unchanged collapsed global state", () => {
  const earlier = new CountingHistoryComponent();
  const tui = createTui(earlier, 0, () => false);
  const block = new FixedSizeExpandable();
  const history = tui.children[0] as Container;
  const earlierRenderCalls = earlier.renderCalls;

  history.addChild(block);
  tui.doRender();

  assert.equal(earlier.renderCalls, earlierRenderCalls);
  assert.ok(tui.previousLines.some((line) => line.includes("more lines")));
});

test("streaming blocks are compacted when their completed output becomes long", () => {
  const block = new GrowingFixedSizeExpandable();
  const tui = createTui(block, 0, () => false);

  block.complete = true;
  block.isPartial = false;
  invalidateStickySplitFooterHistory(tui as unknown as TUI);
  tui.doRender();

  assert.ok(tui.previousLines.some((line) => line.includes("more lines")));
});

test("global state is applied to compact-strategy blocks on render", () => {
  let expanded = false;
  const block = new FixedSizeExpandable();
  const tui = createTui(block, 0, () => expanded);

  assert.ok(tui.previousLines.some((line) => line.includes("more lines")));

  expanded = true;
  block.setExpanded(true); // Pi applies the native global state before rendering.
  tui.doRender();
  assert.ok(tui.previousLines.every((line) => !line.includes("more lines")));
});

test("click rerenders only the selected block", () => {
  const earlier = new CountingHistoryComponent();
  const block = new FixedSizeExpandable();
  const history = new Container();
  history.addChild(earlier);
  history.addChild(block);
  const tui = createTui(history);
  const earlierRenderCalls = earlier.renderCalls;

  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 3), true);

  assert.equal(earlier.renderCalls, earlierRenderCalls);
});

test("global synchronization does not reapply Pi's matching expanded state", () => {
  let expanded = false;
  const block = new CountingShortExpandable();
  const tui = createTui(block, 0, () => expanded);

  block.setExpanded(true); // Pi applies its global state before requesting a render.
  const setExpandedCalls = block.setExpandedCalls;
  expanded = true;
  tui.doRender();

  assert.equal(block.setExpandedCalls, setExpandedCalls);
});

test("global expansion rerenders only expandable blocks", () => {
  const earlier = new CountingHistoryComponent();
  const block = new FixedSizeExpandable();
  const history = new Container();
  history.addChild(earlier);
  history.addChild(block);
  const tui = createTui(history, 0, () => false);
  const earlierRenderCalls = earlier.renderCalls;

  assert.equal(setStickySplitFooterToolsExpanded(tui as unknown as TUI, true), true);

  assert.equal(earlier.renderCalls, earlierRenderCalls);
});

test("incremental global expansion yields before updating all blocks", async () => {
  const blocks = Array.from({ length: 5 }, () => new FixedSizeExpandable());
  const history = new Container();
  for (const block of blocks) history.addChild(block);
  let expanded = false;
  const tui = createTui(history, 0, () => expanded);

  expanded = true;
  assert.equal(setStickySplitFooterToolsExpandedIncrementally(tui as unknown as TUI, true, 1), true);
  assert.equal(blocks.some((block) => block.expanded), false);
  await new Promise((resolve) => setTimeout(resolve, 20));

  assert.equal(blocks.every((block) => block.expanded), true);
});

test("global expansion overrides local compact state and keeps two click states", () => {
  const block = new FixedSizeExpandable();
  const tui = createTui(block);

  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 2), true);
  assert.ok(tui.previousLines.some((line) => line.includes("more lines")));

  assert.equal(setStickySplitFooterToolsExpanded(tui as unknown as TUI, true), true);
  assert.equal(block.expanded, true);
  assert.ok(tui.previousLines.every((line) => !line.includes("more lines")));

  assert.equal(setStickySplitFooterToolsExpanded(tui as unknown as TUI, false), true);
  assert.equal(block.expanded, false);
  assert.ok(tui.previousLines.some((line) => line.includes("more lines")));

  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 2), true);
  assert.equal(block.expanded, true);
  assert.ok(tui.previousLines.every((line) => !line.includes("more lines")));
});

test("click keeps native collapsed/expanded states when native expansion resizes the component", () => {
  const block = new ResizingExpandable();
  const tui = createTui(block);

  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 2), true);
  assert.equal(block.expanded, true);
  assert.ok(tui.previousLines.some((line) => line.includes("detail-7")));
  assert.ok(tui.previousLines.every((line) => !line.includes("more lines")));

  assert.equal(toggleStickySplitFooterComponentAt(tui as unknown as TUI, 2), true);
  assert.equal(block.expanded, false);
  assert.ok(tui.previousLines.some((line) => line.includes("summary")));
  assert.ok(tui.previousLines.every((line) => !line.includes("detail-7")));
});
