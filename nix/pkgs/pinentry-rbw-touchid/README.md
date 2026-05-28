# pinentry-rbw-touchid

Touch-ID-gated pinentry for [rbw](https://github.com/doy/rbw). The Bitwarden
master password is stored in the macOS Keychain on first use; subsequent
unlocks ask for Touch ID via `LAContext.evaluatePolicy` rather than re-typing.

Built by `default.nix` with the host `/usr/bin/swiftc` against the system Xcode
SDK — see that file for why nixpkgs' darwin Swift is avoided.

## Prerequisites

- **Xcode Command Line Tools** (`xcode-select --install`). The build phase
  shells out to `/usr/bin/swiftc`; without CLT the whole `darwin-rebuild` fails.

## New-machine setup (after a successful `darwin-rebuild switch`)

The flake's activation script already installs rbw, pinentry-mac, and this
binary, and points `rbw config` at them with `lock_timeout = 1`. The remaining
steps are interactive — they involve credentials and consent that can't be
declared in nix.

1. **Identify the account**
   ```
   rbw config set email <your-bitwarden-email>
   rbw config set base_url https://vault.bitwarden.eu   # EU accounts only
   ```
2. **Get a personal API key** in the web vault under
   _Account Settings → Security → Keys → View API Key_ (client_id + client_secret).
3. **Register the device** (bypasses Bitwarden's anti-bot 400 on direct logins):
   ```
   rbw register     # pinentry-mac prompts twice; the binary does NOT save these
   ```
4. **Log in**. pinentry-mac asks for the master password, the binary saves it
   to Keychain on the way through:
   ```
   rbw login
   ```
5. The first time the binary reads the Keychain item, macOS prompts to allow
   access. Click **Always Allow**.

From then on: `rbw get <name>` → Touch ID → secret printed → agent re-locks
(via the `rbw()` wrapper in `zsh/.zshrc`).

## Quirks worth knowing

- **The Keychain ACL re-prompts when the binary's bytes change.** macOS ties
  Keychain item ACLs to the caller's code-signing identity, and the nix-built
  binary is ad-hoc signed. Edit `main.swift` (or bump the Swift toolchain) →
  one extra "Always Allow" prompt the next time the binary accesses the item.
  Touch ID itself is unaffected.
- **The master password lives only in the local login keychain** (`security`
  service `rbw`, account `master-password`). It is *not* carried by stow or
  nix-darwin. On a fresh Mac without Migration Assistant, step 4 just plays
  out again — pinentry-mac asks once, Keychain gets seeded, Touch ID from
  then on.
- **`rbw register` is required before `rbw login`** for any account hosted by
  Bitwarden's official servers (vault.bitwarden.com / vault.bitwarden.eu).
  Password-only login is treated as bot traffic and returns 400.
