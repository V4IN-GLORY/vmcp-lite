# Updates need a click in Studio — both halves

Nothing updates on its own. Not the server, not the plugin. It used to: `--auto-install-plugin`
overwrote `%LOCALAPPDATA%\Roblox\Plugins\VMCP.rbxmx` on every launch, and the recommended
install (`npx -y github:...`) re-fetched `main` and ran it on every launch. One compromised
commit would have run on every machine using VMCP, with nobody looking. Now:

## Install once, from a clone

```
git clone https://github.com/V4IN-GLORY/vmcp-lite
cd vmcp-lite && npm install          # builds server/dist and VMCP.rbxmx
claude mcp add vmcp -- node "<path to repo>/server/dist/index.js"
```

Then build the plugin into Studio's folder once (see the README) and restart Studio.

## Server updates

When a Studio edit session connects, the server runs `git fetch` in its own checkout and compares
`HEAD` with the upstream branch. If upstream is ahead it sends
`server/update-available { from, to, commits }` — nothing is merged. The panel shows
**Update server (N commits behind)**. Clicking sends `server/update-apply { commit }` with the
commit it was shown; the server fetches again, refuses if upstream has moved since the offer, and
otherwise does `git merge --ff-only <commit>` and `npm ci` (which rebuilds the server and the
plugin). Restart the Claude session to run the new server.

A checkout with local changes can't fast-forward; the button reports the git error and leaves
everything as it was. A copy that isn't a git checkout is never offered a server update.

## Plugin updates

After `session/hello`, the server compares the `VMCP.rbxmx` bundled next to it with the installed
one. If they differ it sends `plugin/update-available { sha256, destination, fresh, bytes }`. The
panel shows **Update plugin (sha)**. Clicking sends `plugin/update-apply { sha256 }`; the server
re-reads the bundled file, refuses if the sha no longer matches, and otherwise writes it (temp
file + rename). Studio hot-reloads a changed local plugin.

A server update usually brings a new plugin build, so the button offers the server first and the
plugin on the next connect.

Only an authenticated edit session can send either `update-apply`, and only for the exact commit
or sha it was offered. A proxy process, a playtest peer or a bare socket can't.

`VMCP_PLUGINS_DIR` overrides where the plugin is written.
