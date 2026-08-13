/**
 * Pi Notify Publisher
 *
 * Publishes main-agent settled events to the same ntfy.sh topic Claude Code uses.
 * The existing Mac subscriber (claude-code/scripts/notify-subscriber.sh)
 * picks up all messages and fires popup + voice — the "Pi: " prefix lets
 * you distinguish Pi notifications from Claude Code ones.
 *
 * This works regardless of where the pi runtime lives (local or devbox):
 * the publisher POSTs to ntfy.sh, the subscriber on the Mac handles the rest.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { basename } from "node:path";
import { homedir } from "node:os";
import { readFileSync, existsSync } from "node:fs";

// ── config ───────────────────────────────────────────────────────────────────

// Reuse the same ntfy.sh topic Claude Code publishes to.
// Shared topic = shared subscriber = no extra launchd job needed.
const WEBHOOK_PATH = `${homedir()}/.config/claude-code/notify-webhook.url`;

function getWebhookUrl(): string | null {
  if (!existsSync(WEBHOOK_PATH)) return null;
  return readFileSync(WEBHOOK_PATH, "utf-8").trim();
}

// ── publish ──────────────────────────────────────────────────────────────────

async function publish(message: string): Promise<void> {
  const url = getWebhookUrl();
  if (!url) return;

  try {
    await fetch(url, {
      method: "POST",
      body: message,
      signal: AbortSignal.timeout(5000),
    });
  } catch {
    // ntfy.sh unreachable (no network, devbox offline, etc.) — silently skip
  }
}

// ── extension ────────────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  if (process.env.PI_SUBAGENT_CHILD === "1") return;

  pi.on("agent_settled", async (_event, ctx) => {
    const project = basename(ctx.cwd);
    // "Pi: " prefix so voice says "Pi: dotfiles ready" — distinguishable from Claude Code
    publish(`Pi: ${project} ready`);
  });
}