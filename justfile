# LLM coding-agent harnesses on this Mac are not nix/brew-managed uniformly,
# so there's no single `darwin-rebuild` that upgrades them. claude is a
# native-installer binary at ~/.local/bin/claude (self-updates in a normal
# shell); pi-coding-agent is a Homebrew formula that nix-darwin's homebrew
# module does NOT auto-upgrade on activation. See homelab BB.md/AUTOMATION-GAPS.md
# for the devbox-side equivalents (`just bb-update`, `just pi-update`).
harness-update:
    claude update
    brew upgrade pi-coding-agent
