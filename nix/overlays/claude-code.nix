self: super: {
  claude-code = super.claude-code.overrideAttrs (old: rec {
    version = "1.0.34";
    src = super.fetchzip {
      url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
      hash = "sha256-8f7XdvWRMv+icI8GMQW7AAmesdvpr/3SaWCRC723iSs=";
    };
    # dependencies did not change; keep existing hash
    npmDepsHash = old.npmDepsHash;
  });
} 