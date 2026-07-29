import assert from "node:assert/strict";
import test from "node:test";

import { visibleWidth } from "@earendil-works/pi-tui";
import { highlightStickySplitFooterSelection } from "../src/tui/split-footer-renderer.ts";

test("highlights the dragged transcript range without changing line widths", () => {
  const lines = ["alpha", "bravo", "charlie"];
  const highlighted = highlightStickySplitFooterSelection(
    lines,
    { row: 1, column: 3 },
    { row: 2, column: 3 },
    3,
  );

  assert.match(highlighted[0] ?? "", /\x1b\[7mpha\x1b\[27m/);
  assert.match(highlighted[1] ?? "", /\x1b\[7mbra\x1b\[27m/);
  assert.deepEqual(highlighted.map(visibleWidth), lines.map(visibleWidth));
});
