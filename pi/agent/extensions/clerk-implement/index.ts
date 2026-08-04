import { stripFrontmatter, type ExtensionAPI, type SlashCommandInfo } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { dirname } from "node:path";

const NO_WORK_ID = "no Work ID supplied";

function buildWorkflowPrompt(workId: string): string {
	return `Implement Clerk Backlog Work (${workId}).

Follow this repo's Clerk workflow:

1. Run \`clerk doctor\` if setup or the next workflow step is unclear.
2. Resolve exactly one pickable Work item:
   - If no Work ID was supplied, run \`clerk backlog next\`, choose one item, and inspect it with \`clerk backlog show <id>\`.
   - Otherwise, treat the supplied argument (\`${workId}\`) as one pickable Work ID and inspect it with \`clerk backlog show <id>\`.
   - Epic or parent IDs, multiple IDs, and free-form scope are unsupported. Stop rather than trying to resolve or guess them.
   - Let Clerk determine pickability. Do not infer it independently from ready state, parent/child state, or blockers.
3. Claim the Work item with \`clerk backlog claim <id>\`.
4. Change directory to the authoritative worktree path printed on the final line by Claim. Do not construct or guess the path.
5. Implement only that Work item and satisfy its Acceptance criteria; use TDD/test-first where practical. Record unrelated discoveries with \`clerk capture\` instead of expanding scope.
6. Run the relevant checks/tests and commit the work to the current delivery branch.
7. Use \`/skill:code-review\` or the code-review skill to review the completed diff against the fixed point \`origin/main\` before submit.
8. Submit with exactly \`clerk backlog submit <id>\`.
9. If the Project gate is pending, repeat \`clerk backlog gate <id>\` until it reaches a terminal result. If it fails, repair, verify, review, commit, and submit again.
10. Run \`clerk backlog finish <id>\` only when Submission ownership is \`clerk\` and Clerk owns a submitted PR.
11. If the Work item is impossible as refined, use \`clerk backlog return <id> --reason "..."\` rather than improvising scope.`;
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

			const workId = args.trim() || NO_WORK_ID;
			await ctx.waitForIdle();
			pi.sendUserMessage(`${expandSkill(implementSkill)}\n\n${buildWorkflowPrompt(workId)}`);
		},
	});
}
