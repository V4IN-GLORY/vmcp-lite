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

## The Updates section in the panel

Always visible, under the auth token. One row for the server, one for the plugin, each with its
own **Update** button that's only live when there's something to apply, and a **Check** that asks
the server again at any time. The server also pushes the state on every connect and the plugin
prints a line to Output when either half has an update, so you see it without opening the panel.

The state is `updates/state { server, plugin, running, head, git }` (pushed) and the reply to
`updates/check` (on demand):

- **server** — `{ from, to, commits }` when the server's git checkout is behind upstream. The
  server runs `git fetch` to find out; nothing is merged. Clicking Update sends
  `server/update-apply { commit }` with the commit it was shown; the server fetches again, refuses
  if upstream moved since, and otherwise does `git merge --ff-only <commit>` and `npm ci` (which
  rebuilds the server and the plugin). A checkout with local changes can't fast-forward; the
  error shows in the panel and nothing changes.
- **plugin** — `{ sha256, destination, fresh, bytes }` when the `VMCP.rbxmx` bundled next to the
  server differs from the installed one. Clicking Update sends `plugin/update-apply { sha256 }`;
  the server re-reads the bundled file, refuses if the sha no longer matches, and otherwise
  writes it (temp file + rename). Studio hot-reloads a changed local plugin.
- **running / head** — the commit this server process started from vs. what its checkout is at
  now. The server is launched headless by the MCP client, so after a server update it keeps
  running the old build; when the two differ the panel says so and tells you to restart the
  Claude/MCP session. Applying the server update also refreshes the plugin row, since the new
  checkout usually brings a new build.
- **git** — false when the server isn't a git checkout; the row then says to update it by hand.

Only an authenticated edit session can send either `update-apply`, and only for the exact commit
or sha it was offered. A proxy process, a playtest peer or a bare socket can't.

`VMCP_PLUGINS_DIR` overrides where the plugin is written.
