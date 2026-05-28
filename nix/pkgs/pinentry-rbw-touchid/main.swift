// Touch-ID-gated pinentry for rbw.
//
// Speaks just enough of the assuan/pinentry protocol that rbw uses (SETTITLE,
// SETPROMPT, SETDESC, SETERROR, GETPIN — see rbw's src/pinentry.rs). On GETPIN,
// if a master password is in the macOS Keychain we prompt Touch ID via
// LAContext and return it; otherwise we shell out to pinentry-mac for a one-
// time GUI prompt and persist the result.
//
// Why not kSecAccessControl(.biometryCurrentSet)?  An ACL-bound item is tied to
// the calling binary's code-signing identity.  Nix rebuilds produce a binary
// with a new ad-hoc signature → the user would lose access to the stored item
// after every rebuild.  We instead gate Touch ID at the app layer (LAContext)
// and use a plain `kSecAttrAccessibleWhenUnlocked` item.

import Foundation
import LocalAuthentication
import Security

let kcService  = "rbw"
let kcAccount  = "master-password"
// pinentry-mac is installed via nix-darwin (systemPackages), so it lives under
// the system profile. Hardcoding this stable path avoids relying on the rbw-
// agent's PATH (which is whatever launchd hands it, not necessarily the user's
// login PATH).
let fallback   = "/run/current-system/sw/bin/pinentry-mac"

// MARK: - Keychain

func keychainRead() -> String? {
    let q: [String: Any] = [
        kSecClass            as String: kSecClassGenericPassword,
        kSecAttrService      as String: kcService,
        kSecAttrAccount      as String: kcAccount,
        kSecReturnData       as String: true,
        kSecMatchLimit       as String: kSecMatchLimitOne,
    ]
    var item: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

func keychainWrite(_ password: String) {
    let base: [String: Any] = [
        kSecClass       as String: kSecClassGenericPassword,
        kSecAttrService as String: kcService,
        kSecAttrAccount as String: kcAccount,
    ]
    SecItemDelete(base as CFDictionary)
    var attrs = base
    attrs[kSecValueData       as String] = password.data(using: .utf8)!
    attrs[kSecAttrAccessible  as String] = kSecAttrAccessibleWhenUnlocked
    SecItemAdd(attrs as CFDictionary, nil)
}

// MARK: - Touch ID

func touchIDApproved(reason: String) -> Bool {
    let ctx = LAContext()
    ctx.localizedFallbackTitle = ""   // suppress "Enter Password" fallback button
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
        return false
    }
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
        ok = success
        sem.signal()
    }
    sem.wait()
    return ok
}

// MARK: - Assuan percent encoding

func assuanEncode(_ s: String) -> String {
    var out = ""
    for ch in s.utf8 {
        switch ch {
        case 0x25: out += "%25"
        case 0x0A: out += "%0A"
        case 0x0D: out += "%0D"
        default:   out.append(Character(UnicodeScalar(ch)))
        }
    }
    return out
}

func assuanDecode(_ s: String) -> String {
    let bytes = Array(s.utf8)
    var out: [UInt8] = []
    var i = 0
    func hex(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: return c - 0x30
        case 0x41...0x46: return c - 0x41 + 10
        case 0x61...0x66: return c - 0x61 + 10
        default: return nil
        }
    }
    while i < bytes.count {
        if bytes[i] == 0x25, i + 2 < bytes.count,
           let h = hex(bytes[i+1]), let l = hex(bytes[i+2]) {
            out.append(h << 4 | l)
            i += 3
        } else {
            out.append(bytes[i])
            i += 1
        }
    }
    return String(bytes: out, encoding: .utf8) ?? ""
}

// MARK: - pinentry-mac fallback (for first-time entry)

func promptViaPinentryMac(title: String, desc: String, prompt: String) -> String? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: fallback)
    let inp = Pipe(); let out = Pipe()
    task.standardInput  = inp
    task.standardOutput = out
    do { try task.run() } catch { return nil }
    let script =
        "SETTITLE \(title)\n" +
        "SETPROMPT \(prompt)\n" +
        "SETDESC \(desc)\n" +
        "GETPIN\n" +
        "BYE\n"
    inp.fileHandleForWriting.write(script.data(using: .utf8)!)
    try? inp.fileHandleForWriting.close()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if line.hasPrefix("D ") { return assuanDecode(String(line.dropFirst(2))) }
    }
    return nil
}

// MARK: - main loop

let outFH = FileHandle.standardOutput
func reply(_ s: String) {
    outFH.write((s + "\n").data(using: .utf8)!)
}

var title    = "rbw"
var prompt   = "PIN:"
var desc     = ""
var hadError = false   // rbw sends SETERROR before GETPIN on a retry-after-wrong-password attempt

reply("OK Pleased to meet you, gentle user")

while let line = readLine() {
    let (cmd, arg): (String, String) = {
        if let sp = line.firstIndex(of: " ") {
            return (String(line[..<sp]).uppercased(),
                    String(line[line.index(after: sp)...]))
        }
        return (line.uppercased(), "")
    }()

    switch cmd {
    case "SETTITLE":  title  = arg;  reply("OK")
    case "SETPROMPT": prompt = arg;  reply("OK")
    case "SETDESC":   desc   = arg;  reply("OK")
    case "SETERROR":  hadError = true; reply("OK")
    case "GETPIN":
        // Only treat this as "the rbw master password" when the prompt rbw set
        // is exactly the one used for login/unlock. `rbw register` uses
        // "API key client__id" / "API key client__secret"; 2FA uses provider-
        // specific prompts. For those, just proxy pinentry-mac without ever
        // touching the Keychain.
        let isMaster    = (prompt == "Master Password")
        let useKeychain = isMaster && !hadError
        if useKeychain, let pw = keychainRead() {
            if touchIDApproved(reason: "Unlock rbw vault") {
                reply("D " + assuanEncode(pw))
                reply("OK")
            } else {
                reply("ERR 83886179 Operation cancelled <Pinentry>")
            }
        } else if let pw = promptViaPinentryMac(title: title, desc: desc, prompt: prompt) {
            if isMaster { keychainWrite(pw) }
            reply("D " + assuanEncode(pw))
            reply("OK")
        } else {
            reply("ERR 83886179 Operation cancelled <Pinentry>")
        }
        hadError = false
    case "BYE":
        reply("OK closing connection")
        exit(0)
    default:
        // OPTION / SETKEYINFO / SETOK / SETCANCEL / SETNOTOK / RESET / ...
        reply("OK")
    }
}
