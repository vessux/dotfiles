# Matt Pocock skills for Pi

Vendored from <https://github.com/mattpocock/skills> for direct Pi skill loading while Umbel bundle support is unfinished.

- Source commit: ed37663cc5fbef691ddfecd080dff42f7e7e350d
- Source plugin version: 1.2.0
- Included skills: the stable skill list from `.claude-plugin/plugin.json`.
- Local layout: flattened under `skills/<skill-name>/` so harness-provided locations do not depend on category folders like `engineering/` vs `productivity/`.

Update by re-copying the paths listed in `plugin.json` from a fresh clone, then keep them flattened under `skills/<skill-name>/`.
