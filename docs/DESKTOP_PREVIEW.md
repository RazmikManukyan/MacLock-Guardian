# Desktop Preview milestone (v1.2)

This is the first stand-alone native AppKit dashboard. It is intentionally **not** an installer, agent manager, or replacement for v1.1 security watchers. Its service-status panel is read-only.

## Implemented controls
- Refresh service states via `launchctl print gui/<uid>/<label>` (read only)
- Send a single Telegram test message with explicit confirmation
- Request location permission and one fresh location estimate on demand
- Send one Telegram map pin after separate confirmation
- Open the legacy monitor log in Finder (read-only)

## Not implemented
- Managing service startup and shutdown
- Camera testing from inside the GUI
- An installer/updater or migration wizard
- Reliable locked-screen location and camera functionality across all Macs
- A credential vault, Keychain integration, notarization, accessibility review or full security audit

## Future development order
1. Validate the Objective-C app on an Intel Mac running Sonoma (and on Apple Silicon later).
2. Make a read-only camera self-test, completely isolated from live LaunchAgents.
3. Add secure Keychain-based Telegram configuration, with an explicit account setup flow.
4. Create a separate, opt-in replacement-agent pilot on an unused test Mac/account.
5. Only then add guarded Start/Stop controls for new deployments; never auto-manage the legacy monitors.
6. Implement packaged upgrades, automated UI tests, Developer ID signing and notarization before labeling a release stable.
