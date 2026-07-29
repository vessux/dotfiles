export interface StickyMouseScrollConfig {
  mouseScroll: boolean;
  alternateScroll: boolean;
}

export type StickyInputCommandAction =
  | { type: "toggle" }
  | { type: "setMouseScroll"; enabled: boolean }
  | { type: "status" }
  | { type: "help" }
  | { type: "error"; message: string };

const ENABLE_TOKENS = new Set(["on", "enable", "enabled", "mouse", "scroll"]);
const DISABLE_TOKENS = new Set(["off", "disable", "disabled", "native", "select", "selection", "links"]);
const STATUS_TOKENS = new Set(["status", "state"]);
const HELP_TOKENS = new Set(["help", "--help", "-h"]);

function tokenizeArgs(args: string): string[] {
  return args
    .trim()
    .toLowerCase()
    .split(/\s+/)
    .filter((token) => token.length > 0);
}

export function parseStickyInputCommandArgs(args: string): StickyInputCommandAction {
  const tokens = tokenizeArgs(args);

  if (tokens.length === 0 || (tokens.length === 1 && (tokens[0] === "mouse" || tokens[0] === "toggle"))) {
    return { type: "toggle" };
  }

  const normalizedTokens = tokens[0] === "mouse" ? tokens.slice(1) : tokens;
  if (normalizedTokens.length !== 1) {
    return {
      type: "error",
      message: "Usage: /click-scroll [on|off|toggle|status] or /click-scroll mouse [on|off|status].",
    };
  }

  const [token] = normalizedTokens;
  if (token === "toggle") {
    return { type: "toggle" };
  }

  if (HELP_TOKENS.has(token)) {
    return { type: "help" };
  }

  if (STATUS_TOKENS.has(token)) {
    return { type: "status" };
  }

  if (ENABLE_TOKENS.has(token)) {
    return { type: "setMouseScroll", enabled: true };
  }

  if (DISABLE_TOKENS.has(token)) {
    return { type: "setMouseScroll", enabled: false };
  }

  return {
    type: "error",
    message: `Unknown /click-scroll argument '${token}'. Use /click-scroll help.`,
  };
}

export function applyStickyMouseScrollMode(config: StickyMouseScrollConfig, enabled: boolean): void {
  config.mouseScroll = enabled;
  config.alternateScroll = false;
}

export function getStickyMouseScrollStatusMessage(enabled: boolean): string {
  return enabled
    ? "Pi mouse capture is ON. Click toggles blocks and drag copies transcript text. Run /click-scroll off to restore native terminal mouse behavior."
    : "Pi mouse capture is OFF. Native terminal selection and links are preserved.";
}

export function getStickyInputCommandHelp(): string {
  return [
    "pi-click-scroll mouse mode command:",
    "  /click-scroll          Toggle Pi mouse handling",
    "  /click-scroll on       Enable click, drag-copy, and wheel scrolling",
    "  /click-scroll off      Restore native terminal selection/link clicks",
    "  /click-scroll status   Show current mode",
  ].join("\n");
}
