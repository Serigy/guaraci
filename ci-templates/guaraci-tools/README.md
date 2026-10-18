# guaraci-tools CI templates

Staging copy of the workflows for https://github.com/Serigy/guaraci-tools
(monorepo: `packages/vscode`, `packages/paseo`). Copy them into the tools repo:

    cp -r ci-templates/guaraci-tools/.github <tools-repo>/

- `ci.yml`: node 22, `npm ci`, `node --check` on all package JS, `npm test --workspaces --if-present`
  (grammar snapshots via vscode-tmgrammar-snap), `vsce package --no-dependencies`, uploads the `.vsix` artifact.
- `release.yml`: on `v*` tags runs `ci.yml`, builds the `.vsix` and attaches it to the GitHub release.
  Marketplace publishing is gated on the `VSCE_PAT` and `OVSX_PAT` repository secrets (not configured; steps are skipped).

Assumes `packages/vscode` has a `package-lock.json` at the repo root and a `test` npm script for the snapshot tests; adjust if the layout differs.
