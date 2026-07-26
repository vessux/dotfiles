import { stripFrontmatter, type ExtensionAPI, type SlashCommandInfo } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { dirname } from "node:path";

const DEFAULT_SCOPE = "the next pickable Work item";

function buildWorkflowPrompt(scope: string): string {
	return `Implement Clerk Backlog Work: ${scope}.

Follow this repo's Clerk workflow:

1. Run \`clerk doctor\` if setup or the next workflow step is unclear.
2. Resolve the Work item to implement from the supplied arguments (\`${scope}\`):
   - If no arguments were supplied, run \`clerk backlog next\`, choose one pickable Work item, and inspect it with \`clerk backlog show <id>\`.
   - If the arguments include a specific pickable Work ID, inspect it with \`clerk backlog show <id>\`.
   - If the arguments name an epic or another non-pickable parent, inspect it with \`clerk backlog show <id>\`, run \`clerk backlog next\`, and choose the first direct child that appears in that pickable Backlog view and satisfies the supplied instructions. Inspect the chosen child with \`clerk backlog show <child-id>\`.
   - Let Clerk determine pickability. Do not infer it independently from ready state, parent/child state, or blockers.
   - If the requested scope cannot be resolved to exactly one pickable Work item, stop and explain what Clerk command/output blocks selection rather than guessing.
3. Claim the resolved Work item with \`clerk backlog claim <id>\`.
4. Do all implementation work inside the created \`.worktrees/<id>\` worktree, not the repo root.
5. Implement only that resolved Backlog item and satisfy its Acceptance criteria; use TDD/test-first where practical. Record unrelated discoveries with \`clerk capture\` instead of expanding scope.
6. Run the relevant checks/tests.
7. Use \`/skill:code-review\` or the code-review skill to review the completed diff before submit.
8. Run \`clerk --explain backlog submit\`, then invoke \`clerk backlog submit <id>\` with exactly the additional input, if any, prescribed by the current Clerk generation. If Clerk prescribes proof JSON, generate it with \`clerk backlog proof <id>\`, fill in the requested evidence, and pass it to submit.
9. Run \`clerk backlog finish <id>\` until the reconciler reports that the Work item is merged, waiting, or needs another build loop. If another build loop is required, fix and verify the Work before submitting or finishing again.
10. If the resolved Work item is impossible as refined, use \`clerk backlog return <id> --reason "..."\` rather than improvising scope.`;
}

function expandSkill(command: SlashCommandInfo): string {
	const content = readFileSync(command.sourceInfo.path, "utf-8");
	const body = stripFrontmatter(content);
	const baseDir = dirname(command.sourceInfo.path);

	return `<skill name="implement" location="${command.sourceInfo.path}">
References are relative to ${baseDir}.

${body}
</skill>`;
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("clerk-implement", {
		description: "Run the implement skill with this repo's Clerk backlog workflow",
		handler: async (args, ctx) => {
			const implementSkill = pi
				.getCommands()
				.find((command) => command.name === "skill:implement" && command.source === "skill");
			if (!implementSkill) {
				ctx.ui.notify("The implement skill is not loaded; cannot run Clerk implement workflow.", "error");
				return;
			}

			const scope = args.trim() || DEFAULT_SCOPE;
			await ctx.waitForIdle();
			pi.sendUserMessage(`${expandSkill(implementSkill)}\n\n${buildWorkflowPrompt(scope)}`);
		},
	});
}
