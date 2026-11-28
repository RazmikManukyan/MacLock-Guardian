# Publishing v1.1.0-alpha.1 on GitHub

**Do not push the private `~/.mac-security` or `~/.maclock-guardian` directories.** The release ZIP includes source files only.

**Easiest method:** after extracting the ZIP in Downloads, open Terminal and run:

```bash
cd ~/Downloads/MacLock-Guardian-v1.1
bash scripts/publish-github.sh
```

The script clones a fresh Git working folder, stages only project source, shows staged files and asks for the exact word `PUBLISH` before committing and pushing. It refuses to overwrite an existing publication folder. No force push or release tag is created.

**Manual method:**

1. Download and extract the prepared `MacLock-Guardian-v1.1.0-alpha.1.zip` in `~/Downloads`.
2. Check `gh auth status` (GitHub CLI must be signed in). Never share a token or authentication code.
3. Clone the GitHub repository into a **new, empty** working directory:

   ```bash
   git clone https://github.com/RazmikManukyan/MacLock-Guardian.git ~/Documents/MacLock-Guardian-v11-Publish
   ```

   If the directory already exists, do **not** overwrite it; inspect it first.

4. Copy the update into the clone without touching its `.git` directory:

   ```bash
   cp -R ~/Downloads/MacLock-Guardian-v1.1/. ~/Documents/MacLock-Guardian-v11-Publish/
   cd ~/Documents/MacLock-Guardian-v11-Publish
   bash tests/smoke.sh
   git status --short
   ```

5. Verify the staged paths are project source, never personal credentials or photos:

   ```bash
   git add README.md CONTRIBUTING.md LICENSE VERSION .gitignore Info-Location.plist src scripts tests docs
   git diff --cached --stat
   git diff --cached --check
   git commit -m "MacLock Guardian v1.1 alpha: opt-in location and monitoring"
   git push -u origin main
   ```

6. Open the repository on GitHub and verify `VERSION` reads `1.1.0-alpha.1`. Do not tag a stable v1.1 until independent macOS testing succeeds. Optionally create the **pre-release** tag `v1.1.0-alpha.1` on the GitHub Releases page after validation.

If push fails due to credentials, run `gh auth login` and `gh auth setup-git` on your own Mac, then retry. If it says non-fast-forward or shows a merge issue, **stop**, don't force push.
