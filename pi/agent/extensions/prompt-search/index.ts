import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CustomEditor, DynamicBorder } from "@earendil-works/pi-coding-agent";
import {
	Input,
	Key,
	matchesKey,
	truncateToWidth,
	type Component,
	type Focusable,
} from "@earendil-works/pi-tui";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const MAX_RESULTS = 200;
const DEFAULT_VISIBLE_RESULTS = 12;

type PromptSource = "branch" | "session" | "history";
type PromptKind = "prompt" | "bash";
type SearchScope = "all" | "sessions" | "current" | "history";
type ContentScope = "all" | "prompts" | "bash";

interface PromptCandidate {
	key: string;
	source: PromptSource;
	kind: PromptKind;
	text: string;
	timestamp: number;
	entryId?: string;
	cwd?: string;
	occurrences: number;
}

interface SearchCollections {
	current: PromptCandidate[];
	stored: PromptCandidate[];
	history: PromptCandidate[];
}

interface SearchOptions {
	scope: SearchScope;
	content: ContentScope;
}

function parseArgs(args: string): { query: string; options: SearchOptions } {
	const tokens = args.trim().split(/\s+/).filter(Boolean);
	const queryParts: string[] = [];
	let scope: SearchScope = "all";
	let content: ContentScope = "all";

	for (const token of tokens) {
		if (token === "--session-only" || token === "--session") {
			scope = "sessions";
			continue;
		}
		if (token === "--current-only" || token === "--current") {
			scope = "current";
			continue;
		}
		if (token === "--history-only" || token === "--history") {
			scope = "history";
			continue;
		}
		if (token === "--bash-only" || token === "--bash") {
			content = "bash";
			continue;
		}
		if (token === "--prompts-only" || token === "--prompts") {
			content = "prompts";
			continue;
		}
		queryParts.push(token);
	}

	return { query: queryParts.join(" "), options: { scope, content } };
}

function contentToText(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";

	return content
		.map((block) => {
			if (!block || typeof block !== "object") return "";
			const typed = block as { type?: unknown; text?: unknown };
			if (typed.type === "text" && typeof typed.text === "string") return typed.text;
			if (typed.type === "image") return "[image]";
			return "";
		})
		.filter(Boolean)
		.join("\n")
		.trim();
}

function normalizePrompt(text: string): string {
	return text.replace(/\s+/g, " ").trim().toLowerCase();
}

function addCandidate(map: Map<string, PromptCandidate>, candidate: Omit<PromptCandidate, "key" | "occurrences">) {
	const normalized = normalizePrompt(candidate.text);
	if (!normalized) return;

	const key = `${candidate.source}:${candidate.kind}:${normalized}`;
	const existing = map.get(key);
	if (existing) {
		existing.occurrences += 1;
		if (candidate.timestamp > existing.timestamp) {
			existing.timestamp = candidate.timestamp;
			existing.entryId = candidate.entryId ?? existing.entryId;
			existing.cwd = candidate.cwd ?? existing.cwd;
		}
		return;
	}

	map.set(key, { ...candidate, key, occurrences: 1 });
}

function bashText(message: { command?: unknown; excludeFromContext?: unknown }): string {
	if (typeof message.command !== "string" || !message.command.trim()) return "";
	return `${message.excludeFromContext ? "!!" : "!"}${message.command.trim()}`;
}

function collectCurrentSessionPrompts(ctx: ExtensionContext): PromptCandidate[] {
	const branchIds = new Set(ctx.sessionManager.getBranch().map((entry) => entry.id));
	const map = new Map<string, PromptCandidate>();

	for (const entry of ctx.sessionManager.getEntries()) {
		if (entry.type !== "message") continue;
		const message = entry.message;
		if (!("role" in message)) continue;

		let text = "";
		let kind: PromptKind = "prompt";
		if (message.role === "user") {
			text = contentToText(message.content);
		} else if (message.role === "bashExecution") {
			text = bashText(message);
			kind = "bash";
		} else {
			continue;
		}
		if (!text) continue;

		addCandidate(map, {
			source: branchIds.has(entry.id) ? "branch" : "session",
			kind,
			text,
			timestamp: typeof message.timestamp === "number" ? message.timestamp : Date.parse(entry.timestamp),
			entryId: entry.id,
			cwd: ctx.cwd,
		});
	}

	return Array.from(map.values());
}

function collectStoredSessionPrompts(ctx: ExtensionContext): PromptCandidate[] {
	const sessionDir = ctx.sessionManager.getSessionDir();
	if (!sessionDir || !existsSync(sessionDir)) return [];

	const currentSessionFile = ctx.sessionManager.getSessionFile();
	const currentSessionPath = currentSessionFile ? resolve(currentSessionFile) : undefined;
	const currentCwd = resolve(ctx.sessionManager.getCwd());
	const map = new Map<string, PromptCandidate>();

	let fileNames: string[];
	try {
		fileNames = readdirSync(sessionDir).filter((name) => name.endsWith(".jsonl"));
	} catch {
		return [];
	}

	for (const fileName of fileNames) {
		const path = join(sessionDir, fileName);
		if (currentSessionPath && resolve(path) === currentSessionPath) continue;

		let lines: string[];
		try {
			lines = readFileSync(path, "utf8").split(/\r?\n/);
		} catch {
			continue;
		}

		let sessionCwd: string | undefined;
		for (const line of lines) {
			if (!line.trim()) continue;
			try {
				const entry = JSON.parse(line) as {
					type?: unknown;
					id?: unknown;
					timestamp?: unknown;
					cwd?: unknown;
					message?: {
						role?: unknown;
						content?: unknown;
						command?: unknown;
						excludeFromContext?: unknown;
						timestamp?: unknown;
					};
				};

				if (entry.type === "session") {
					if (typeof entry.cwd === "string") sessionCwd = resolve(entry.cwd);
					if (sessionCwd !== currentCwd) break;
					continue;
				}

				if (sessionCwd !== currentCwd) continue;
				if (entry.type !== "message") continue;
				if (!entry.message) continue;

				let text = "";
				let kind: PromptKind = "prompt";
				if (entry.message.role === "user") {
					text = contentToText(entry.message.content);
				} else if (entry.message.role === "bashExecution") {
					text = bashText(entry.message);
					kind = "bash";
				} else {
					continue;
				}
				if (!text) continue;

				addCandidate(map, {
					source: "session",
					kind,
					text,
					timestamp:
						typeof entry.message.timestamp === "number"
							? entry.message.timestamp
							: typeof entry.timestamp === "string"
								? Date.parse(entry.timestamp)
								: 0,
					entryId: typeof entry.id === "string" ? entry.id : undefined,
					cwd: sessionCwd,
				});
			} catch {
				// Ignore malformed session lines.
			}
		}
	}

	return Array.from(map.values());
}

function historyPaths(): string[] {
	return [
		join(homedir(), ".pi", "agent", "pi-history.jsonl"),
		join(homedir(), ".config", "pi", "agent", "pi-history.jsonl"),
	];
}

function collectHistoryPrompts(): PromptCandidate[] {
	const map = new Map<string, PromptCandidate>();

	for (const path of historyPaths()) {
		if (!existsSync(path)) continue;

		const lines = readFileSync(path, "utf8").split(/\r?\n/);
		for (const line of lines) {
			if (!line.trim()) continue;

			try {
				const entry = JSON.parse(line) as { text?: unknown; timestamp?: unknown; cwd?: unknown };
				if (typeof entry.text !== "string" || !entry.text.trim()) continue;

				addCandidate(map, {
					source: "history",
					kind: entry.text.trim().startsWith("!") ? "bash" : "prompt",
					text: entry.text,
					timestamp: typeof entry.timestamp === "number" ? entry.timestamp : 0,
					cwd: typeof entry.cwd === "string" ? entry.cwd : undefined,
				});
			} catch {
				// Ignore malformed history lines.
			}
		}
	}

	return Array.from(map.values());
}

function fuzzyScore(query: string, text: string): number {
	const normalizedQuery = normalizePrompt(query);
	if (!normalizedQuery) return 1;

	const normalizedText = normalizePrompt(text);
	const tokens = normalizedQuery.split(" ").filter(Boolean);
	let total = 0;

	for (const token of tokens) {
		const score = fuzzyTokenScore(token, normalizedText);
		if (score === Number.NEGATIVE_INFINITY) return score;
		total += score;
	}

	return total;
}

function fuzzyTokenScore(token: string, text: string): number {
	const exactIndex = text.indexOf(token);
	if (exactIndex >= 0) {
		const boundaryBonus = exactIndex === 0 || /[\s/_.:-]/.test(text[exactIndex - 1] ?? "") ? 120 : 0;
		return 1500 + boundaryBonus - Math.min(exactIndex, 500) + token.length * 8;
	}

	let tokenIndex = 0;
	let firstMatch = -1;
	let previousMatch = -1;
	let score = 0;
	let gaps = 0;

	for (let textIndex = 0; textIndex < text.length && tokenIndex < token.length; textIndex++) {
		if (text[textIndex] !== token[tokenIndex]) continue;

		if (firstMatch === -1) firstMatch = textIndex;
		if (previousMatch >= 0) {
			const gap = textIndex - previousMatch - 1;
			gaps += gap;
			score += gap === 0 ? 35 : Math.max(1, 15 - gap);
		}

		if (textIndex === 0 || /[\s/_.:-]/.test(text[textIndex - 1] ?? "")) score += 30;
		score += 20;
		previousMatch = textIndex;
		tokenIndex += 1;
	}

	if (tokenIndex !== token.length) return Number.NEGATIVE_INFINITY;
	return 500 + score - Math.min(firstMatch, 300) - Math.min(gaps, 300);
}

function rankCandidates(query: string, candidates: PromptCandidate[]): PromptCandidate[] {
	const normalizedQuery = normalizePrompt(query);
	const ranked = candidates
		.map((candidate) => ({ candidate, score: fuzzyScore(query, candidate.text) }))
		.filter((item) => item.score !== Number.NEGATIVE_INFINITY)
		.sort((a, b) => {
			if (b.score !== a.score) return b.score - a.score;
			if (!normalizedQuery) return b.candidate.timestamp - a.candidate.timestamp;
			if (b.candidate.source !== a.candidate.source) {
				const priority: Record<PromptSource, number> = { branch: 3, session: 2, history: 1 };
				return priority[b.candidate.source] - priority[a.candidate.source];
			}
			return b.candidate.timestamp - a.candidate.timestamp;
		})
		.slice(0, MAX_RESULTS)
		.map((item) => item.candidate);

	// Display worst/oldest at the top and best/newest at the bottom, so pressing
	// ↑ from the initial selection walks deeper into history like shell history.
	return ranked.reverse();
}

function formatTime(timestamp: number): string {
	if (!timestamp) return "unknown";
	const date = new Date(timestamp);
	if (Number.isNaN(date.getTime())) return "unknown";
	return date.toLocaleString(undefined, {
		month: "short",
		day: "2-digit",
		hour: "2-digit",
		minute: "2-digit",
	});
}

function oneLine(text: string): string {
	return text.replace(/\s+/g, " ").trim();
}

class PromptSearchComponent implements Component, Focusable {
	private input = new Input();
	private scopeCandidates: PromptCandidate[] = [];
	private filtered: PromptCandidate[] = [];
	private selectedIndex = 0;
	private visibleResults = DEFAULT_VISIBLE_RESULTS;
	private focusedValue = false;

	constructor(
		private collections: SearchCollections,
		private scope: SearchScope,
		private content: ContentScope,
		initialQuery: string,
		private theme: any,
		private keybindings: { matches: (data: string, id: string) => boolean },
		private done: (candidate: PromptCandidate | null) => void,
	) {
		this.input.setValue(initialQuery);
		this.input.onSubmit = () => this.selectCurrent();
		this.input.onEscape = () => this.done(null);
		this.recompute();
	}

	get focused(): boolean {
		return this.focusedValue;
	}

	set focused(value: boolean) {
		this.focusedValue = value;
		this.input.focused = value;
	}

	handleInput(data: string): void {
		if (this.keybindings.matches(data, "tui.select.up") || matchesKey(data, Key.ctrl("p"))) {
			this.move(-1);
			return;
		}
		if (this.keybindings.matches(data, "tui.select.down") || matchesKey(data, Key.ctrl("n"))) {
			this.move(1);
			return;
		}
		if (this.keybindings.matches(data, "tui.select.pageUp")) {
			this.move(-this.visibleResults);
			return;
		}
		if (this.keybindings.matches(data, "tui.select.pageDown")) {
			this.move(this.visibleResults);
			return;
		}
		if (matchesKey(data, Key.tab)) {
			this.cycleScope(1);
			return;
		}
		if (matchesKey(data, Key.shift("tab"))) {
			this.cycleScope(-1);
			return;
		}
		if (matchesKey(data, Key.ctrl("b"))) {
			this.cycleContent();
			return;
		}
		if (this.keybindings.matches(data, "tui.select.confirm")) {
			this.selectCurrent();
			return;
		}
		if (this.keybindings.matches(data, "tui.select.cancel")) {
			this.done(null);
			return;
		}

		const previous = this.input.getValue();
		this.input.handleInput(data);
		if (this.input.getValue() !== previous) this.recompute();
	}

	render(width: number): string[] {
		const lines: string[] = [];
		const safeWidth = Math.max(20, width);

		lines.push(...new DynamicBorder((str: string) => this.theme.fg("accent", str)).render(safeWidth));
		lines.push(truncateToWidth(this.theme.fg("accent", this.theme.bold("Prompt search")), safeWidth, ""));
		lines.push(...this.renderInput(safeWidth));
		lines.push(this.theme.fg("muted", truncateToWidth(`Scope: ${scopeLabel(this.scope)} • Content: ${contentLabel(this.content)}`, safeWidth, "")));
		lines.push(this.theme.fg("dim", truncateToWidth(`${this.filtered.length}/${this.scopeCandidates.length} matches • ${collectionCounts(this.collections)}`, safeWidth, "")));

		if (this.filtered.length === 0) {
			lines.push(this.theme.fg("warning", "  No matching prompts"));
		} else {
			const start = Math.max(
				0,
				Math.min(this.selectedIndex - Math.floor(this.visibleResults / 2), this.filtered.length - this.visibleResults),
			);
			const end = Math.min(start + this.visibleResults, this.filtered.length);

			for (let index = start; index < end; index++) {
				const candidate = this.filtered[index];
				if (!candidate) continue;
				lines.push(this.renderCandidate(candidate, index === this.selectedIndex, safeWidth));
			}

			const selected = this.filtered[this.selectedIndex];
			if (selected) {
				lines.push("");
				lines.push(this.theme.fg("muted", truncateToWidth("Preview:", safeWidth, "")));
				for (const previewLine of selected.text.split(/\r?\n/).slice(0, 4)) {
					lines.push(`  ${truncateToWidth(previewLine, Math.max(1, safeWidth - 2), "…")}`);
				}
				if (selected.text.split(/\r?\n/).length > 4) lines.push(this.theme.fg("dim", "  …"));
			}
		}

		lines.push("");
		lines.push(
			this.theme.fg(
				"dim",
				truncateToWidth("Type to fuzzy filter • Tab/Shift+Tab scope • ↑↓/Ctrl+P/Ctrl+N move • Enter load • Esc cancel", safeWidth, ""),
			),
		);
		lines.push(...new DynamicBorder((str: string) => this.theme.fg("accent", str)).render(safeWidth));
		return lines.map((line) => truncateToWidth(line, safeWidth, ""));
	}

	invalidate(): void {
		this.input.invalidate();
	}

	private renderInput(width: number): string[] {
		const prefix = "Query: ";
		const inputWidth = Math.max(1, width - prefix.length);
		const [inputLine = ""] = this.input.render(inputWidth);
		return [truncateToWidth(prefix + inputLine, width, "")];
	}

	private renderCandidate(candidate: PromptCandidate, selected: boolean, width: number): string {
		const prefix = selected ? "→ " : "  ";
		const source = candidate.source === "branch" ? "current" : candidate.source;
		const kind = candidate.kind === "bash" ? "bash" : "prompt";
		const meta = `[${source}/${kind} ${formatTime(candidate.timestamp)}]`;
		const suffix = candidate.occurrences > 1 ? ` (${candidate.occurrences}x)` : "";
		const availableTextWidth = Math.max(1, width - prefix.length - meta.length - suffix.length - 2);
		const line = `${prefix}${meta} ${truncateToWidth(oneLine(candidate.text), availableTextWidth, "…")}${suffix}`;
		return selected ? this.theme.fg("accent", line) : line;
	}

	private recompute(): void {
		this.scopeCandidates = getScopedCandidates(this.collections, this.scope, this.content);
		this.filtered = rankCandidates(this.input.getValue(), this.scopeCandidates);
		this.selectedIndex = Math.max(0, this.filtered.length - 1);
	}

	private cycleScope(direction: 1 | -1): void {
		const scopes: SearchScope[] = ["all", "sessions", "current", "history"];
		const index = scopes.indexOf(this.scope);
		this.scope = scopes[(index + direction + scopes.length) % scopes.length] ?? "all";
		this.recompute();
	}

	private cycleContent(): void {
		const contentScopes: ContentScope[] = ["all", "prompts", "bash"];
		const index = contentScopes.indexOf(this.content);
		this.content = contentScopes[(index + 1) % contentScopes.length] ?? "all";
		this.recompute();
	}

	private move(delta: number): void {
		if (this.filtered.length === 0) return;
		this.selectedIndex = (this.selectedIndex + delta + this.filtered.length) % this.filtered.length;
	}

	private selectCurrent(): void {
		const selected = this.filtered[this.selectedIndex];
		if (selected) this.done(selected);
	}
}

function sourcePriority(source: PromptSource): number {
	return source === "branch" ? 3 : source === "session" ? 2 : 1;
}

function mergePromptLists(candidates: PromptCandidate[]): PromptCandidate[] {
	const byText = new Map<string, PromptCandidate>();

	for (const candidate of candidates) {
		const key = `${candidate.kind}:${normalizePrompt(candidate.text)}`;
		const existing = byText.get(key);
		if (!existing) {
			byText.set(key, { ...candidate });
			continue;
		}

		existing.occurrences += candidate.occurrences;
		if (candidate.timestamp > existing.timestamp) existing.timestamp = candidate.timestamp;

		if (sourcePriority(candidate.source) > sourcePriority(existing.source)) {
			existing.source = candidate.source;
			existing.entryId = candidate.entryId ?? existing.entryId;
			existing.cwd = candidate.cwd ?? existing.cwd;
		}
	}

	return Array.from(byText.values());
}

function buildSearchCollections(ctx: ExtensionContext): SearchCollections {
	return {
		current: collectCurrentSessionPrompts(ctx),
		stored: collectStoredSessionPrompts(ctx),
		history: collectHistoryPrompts(),
	};
}

function filterContent(candidates: PromptCandidate[], content: ContentScope): PromptCandidate[] {
	if (content === "all") return candidates;
	const kind: PromptKind = content === "bash" ? "bash" : "prompt";
	return candidates.filter((candidate) => candidate.kind === kind);
}

function getScopedCandidates(collections: SearchCollections, scope: SearchScope, content: ContentScope): PromptCandidate[] {
	let scoped: PromptCandidate[];
	switch (scope) {
		case "all":
			scoped = [...collections.current, ...collections.stored, ...collections.history];
			break;
		case "sessions":
			scoped = [...collections.current, ...collections.stored];
			break;
		case "current":
			scoped = collections.current;
			break;
		case "history":
			scoped = collections.history;
			break;
	}
	return mergePromptLists(filterContent(scoped, content));
}

function scopeLabel(scope: SearchScope): string {
	switch (scope) {
		case "all":
			return "all (current session + same-project stored sessions + pi-history)";
		case "sessions":
			return "sessions (current session + same-project stored sessions)";
		case "current":
			return "current session tree only";
		case "history":
			return "pi-history only";
	}
}

function contentLabel(content: ContentScope): string {
	switch (content) {
		case "all":
			return "all (prompts + !/!! bash)";
		case "prompts":
			return "prompts only";
		case "bash":
			return "!/!! bash only";
	}
}

function countKind(candidates: PromptCandidate[], kind: PromptKind): number {
	return candidates.filter((candidate) => candidate.kind === kind).length;
}

function collectionCounts(collections: SearchCollections): string {
	const all = [...collections.current, ...collections.stored, ...collections.history];
	return `current ${collections.current.length}, stored ${collections.stored.length}, history ${collections.history.length}, prompts ${countKind(all, "prompt")}, bash ${countKind(all, "bash")}`;
}

async function runPromptSearch(args: string, ctx: ExtensionContext) {
	if (ctx.mode !== "tui") {
		ctx.ui.notify("/prompt-search requires TUI mode", "error");
		return;
	}

	const { query, options } = parseArgs(args);
	const collections = buildSearchCollections(ctx);
	const hasAnyCandidates = getScopedCandidates(collections, "all", "all").length > 0;
	if (!hasAnyCandidates) {
		ctx.ui.notify("No previous prompts found", "warning");
		return;
	}

	const selected = await ctx.ui.custom<PromptCandidate | null>(
		(tui, theme, keybindings, done) => {
			const component = new PromptSearchComponent(collections, options.scope, options.content, query, theme, keybindings, done);
			return {
				render(width: number) {
					return component.render(width);
				},
				invalidate() {
					component.invalidate();
				},
				handleInput(data: string) {
					component.handleInput(data);
					tui.requestRender();
				},
			};
		},
		{
			overlay: true,
			overlayOptions: {
				anchor: "bottom-center",
				width: "100%",
				margin: { top: 1, right: 0, bottom: 1, left: 0 },
			},
		},
	);

	if (!selected) return;

	ctx.ui.setEditorText(selected.text);
	ctx.ui.notify("Prompt loaded into editor", "info");
}

class SearchOnEmptyUpEditor extends CustomEditor {
	constructor(
		tui: any,
		theme: any,
		keybindings: any,
		private openSearch: () => void,
	) {
		super(tui, theme, keybindings);
	}

	handleInput(data: string): void {
		if (matchesKey(data, Key.up) && this.getText().trim().length === 0) {
			this.openSearch();
			return;
		}

		super.handleInput(data);
	}
}

export default function promptSearchExtension(pi: ExtensionAPI) {
	pi.registerCommand("prompt-search", {
		description: "Fuzzy-search previous prompts and load one into the editor",
		handler: runPromptSearch,
	});

	pi.registerCommand("prompts", {
		description: "Alias for /prompt-search",
		handler: runPromptSearch,
	});

	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		const previousEditorFactory = ctx.ui.getEditorComponent();
		const openSearch = () => void runPromptSearch("", ctx);

		ctx.ui.setEditorComponent((tui, theme, keybindings) => {
			const previousEditor = previousEditorFactory?.(tui, theme, keybindings);
			if (!previousEditor) {
				return new SearchOnEmptyUpEditor(tui, theme, keybindings, openSearch);
			}

			return {
				get focused() {
					return Boolean((previousEditor as Partial<Focusable>).focused);
				},
				set focused(value: boolean) {
					(previousEditor as Partial<Focusable>).focused = value;
				},
				render(width: number) {
					return previousEditor.render(width);
				},
				invalidate() {
					previousEditor.invalidate();
				},
				handleInput(data: string) {
					if (matchesKey(data, Key.up) && ctx.ui.getEditorText().trim().length === 0) {
						openSearch();
						return;
					}

					previousEditor.handleInput?.(data);
				},
			} satisfies Component & Focusable;
		});
	});
}
