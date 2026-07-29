import assert from "node:assert/strict";
import test from "node:test";

import {
  advanceStickyMouseSelection,
  parseStickyMouseEvent,
  parseStickyMouseEvents,
  type StickyMouseSelection,
} from "../src/tui/mouse.ts";

test("parses left click, drag, release, and wheel events", () => {
  assert.deepEqual(parseStickyMouseEvent("\x1b[<0;12;7M"), {
    kind: "press", button: 0, column: 12, row: 7, direction: undefined,
  });
  assert.deepEqual(parseStickyMouseEvent("\x1b[<32;18;9M"), {
    kind: "drag", button: 0, column: 18, row: 9, direction: undefined,
  });
  assert.deepEqual(parseStickyMouseEvent("\x1b[<0;18;9m"), {
    kind: "release", button: 0, column: 18, row: 9, direction: undefined,
  });
  assert.deepEqual(parseStickyMouseEvent("\x1b[<64;5;3M"), {
    kind: "wheel", button: 64, column: 5, row: 3, direction: "up",
  });
});

test("parses every event in a batched drag input chunk", () => {
  assert.deepEqual(
    parseStickyMouseEvents("\x1b[<0;12;7M\x1b[<32;18;9M\x1b[<0;18;9m"),
    [
      { kind: "press", button: 0, column: 12, row: 7, direction: undefined },
      { kind: "drag", button: 0, column: 18, row: 9, direction: undefined },
      { kind: "release", button: 0, column: 18, row: 9, direction: undefined },
    ],
  );
});

test("treats a press and release without drag motion as a click", () => {
  const selection: StickyMouseSelection = {};

  assert.equal(advanceStickyMouseSelection(selection, parseStickyMouseEvent("\x1b[<0;12;7M")!), "start");
  assert.deepEqual(advanceStickyMouseSelection(selection, parseStickyMouseEvent("\x1b[<0;13;7m")!), {
    type: "click",
    point: { column: 12, row: 7 },
  });
});

test("tracks drag motion and returns the copy range on release", () => {
  const selection: StickyMouseSelection = {};

  advanceStickyMouseSelection(selection, parseStickyMouseEvent("\x1b[<0;12;7M")!);
  assert.deepEqual(advanceStickyMouseSelection(selection, parseStickyMouseEvent("\x1b[<32;18;9M")!), {
    type: "drag",
    start: { column: 12, row: 7 },
    end: { column: 18, row: 9 },
  });
  assert.deepEqual(advanceStickyMouseSelection(selection, parseStickyMouseEvent("\x1b[<0;18;9m")!), {
    type: "copy",
    start: { column: 12, row: 7 },
    end: { column: 18, row: 9 },
  });
});

test("ignores non-mouse input", () => {
  assert.equal(parseStickyMouseEvent("hello"), undefined);
});
