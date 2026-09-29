# Code signing (Windows, macOS) — how to switch it on

Unsigned games work, but on first launch Windows SmartScreen says *"Windows
protected your PC"* and macOS says the app *"can't be opened because Apple
cannot check it"*. Signing removes those warnings. The release workflow
(`.github/workflows/release.yml`) already contains the signing steps; they
stay **off until you add the secrets below**, and builds are published
unsigned exactly as before.

Add secrets in GitHub: **repository → Settings → Secrets and variables →
Actions → New repository secret**. Never commit certificates or passwords.

## Windows

Since June 2023 new code-signing certificates must keep their private key on
a hardware token or a cloud HSM, so a plain `.pfx` file usually can't be
exported any more. Two options:

### A. Azure Trusted Signing (recommended, ~US$10/month)

Microsoft's signing service, made for CI. Signed files also build SmartScreen
reputation quickly.

1. Create an Azure account → **Trusted Signing account** → complete identity
   validation (individual or organisation) → create a **certificate profile**
   (Public Trust).
2. Create an app registration (service principal) with the role *Trusted
   Signing Certificate Profile Signer* on the account.
3. Add these secrets:

| Secret | Value |
|--------|-------|
| `AZURE_TENANT_ID` | Directory (tenant) ID |
| `AZURE_CLIENT_ID` | App registration's client ID |
| `AZURE_CLIENT_SECRET` | Its client secret |
| `TRUSTED_SIGNING_ENDPOINT` | e.g. `https://eus.codesigning.azure.net/` (your region) |
| `TRUSTED_SIGNING_ACCOUNT` | Trusted Signing account name |
| `TRUSTED_SIGNING_PROFILE` | Certificate profile name |

### B. An exportable `.pfx` certificate (older OV/EV certificates)

| Secret | Value |
|--------|-------|
| `WINDOWS_CERT_PFX_BASE64` | `base64 -w0 cert.pfx` (PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("cert.pfx"))`) |
| `WINDOWS_CERT_PASSWORD` | The .pfx password |

If both are set, Azure Trusted Signing is used. Signed: `StrikeOps.exe`, the
Opus DLL, and the installer; the Windows zip is re-packed with the signed files.

## macOS (Apple Developer Program, US$99/year)

1. Join the Apple Developer Program. In *Certificates, IDs & Profiles* create a
   **Developer ID Application** certificate, install it in Keychain Access and
   export it (with its private key) as `cert.p12`.
2. Create an **app-specific password** at appleid.apple.com (for notarization).
3. Add these secrets:

| Secret | Value |
|--------|-------|
| `MACOS_CERT_P12_BASE64` | `base64 -i cert.p12` |
| `MACOS_CERT_PASSWORD` | The .p12 export password |
| `MACOS_SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Your Apple ID e-mail |
| `APPLE_TEAM_ID` | 10-character team ID |
| `APPLE_APP_PASSWORD` | The app-specific password |

4. Add the repository **variable** (not secret) `MACOS_SIGNING` = `true`
   (*Settings → Secrets and variables → Actions → Variables*).

The `macos-sign` job then signs the Opus libraries and the app with the
hardened runtime (entitlements: microphone only — `installer/macos/entitlements.plist`),
notarizes it with Apple, staples the ticket, and replaces the macOS zip. If it
fails, the release is **not** published (no silent unsigned fallback).

## Checksums (optional)

`GPG_PRIVATE_KEY` (ASCII-armoured) + `GPG_PASSPHRASE` → the release also gets
`SHA256SUMS.asc`. Players verify with `gpg --verify SHA256SUMS.asc SHA256SUMS`.

## Test it before a real release

Run the *Release* workflow by hand (*Actions → Release → Run workflow*): it
builds and signs everything and uploads the files as workflow artifacts, but
only publishes a GitHub Release for `v*` tags. Check the logs of *Windows
installer (+ signing)* and *macOS signing + notarization*, then download the
artifacts and check: Windows — right-click the exe → Properties → Digital
Signatures; macOS — `spctl --assess --verbose "Strike Ops.app"`.

> These steps were written without real certificates, so they have only been
> checked for syntax (actionlint). Do the test run above the first time.
