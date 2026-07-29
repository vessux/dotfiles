import assert from "node:assert/strict";
import test from "node:test";

import { createCopyFeedback } from "../src/tui/copy-feedback.ts";

test("copy feedback disappears after two seconds", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const statuses: Array<string | undefined> = [];
  const feedback = createCopyFeedback({
    setStatus: (_key, text) => statuses.push(text),
  });

  feedback.show("Copied selection");
  assert.deepEqual(statuses, ["Copied selection"]);

  t.mock.timers.tick(2_000);
  assert.deepEqual(statuses, ["Copied selection", undefined]);
});
