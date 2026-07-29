import assert from "node:assert/strict";
import test from "node:test";

import {
  activateStickyTerminalSession,
  deactivateStickyTerminalSession,
} from "../src/tui/terminal-session.ts";

test("restores Pi's Kitty keyboard protocol after entering the alternate screen", () => {
  const writes: string[] = [];
  const tui = {
    terminal: {
      kittyProtocolActive: true,
      write: (data: string) => writes.push(data),
    },
    requestRender() {},
    stop() {},
  };

  try {
    activateStickyTerminalSession(tui as never, {
      alternateScreen: true,
      alternateScroll: false,
      mouseScroll: true,
    });

    assert.match(writes[0] ?? "", /\x1b\[>7u/);
  } finally {
    deactivateStickyTerminalSession();
  }
});
