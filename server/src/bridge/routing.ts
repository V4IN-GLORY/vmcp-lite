import type { Session } from "./session.js";

/**
 * Picks the DataModel a call belongs to.
 *
 * One Studio window is several live sessions once a playtest starts: the edit DataModel, the test
 * server, and one per test client. They all run the same plugin and know the same tools, so a tool
 * name doesn't say where it should run — the `context` argument does.
 */

export interface Routed {
	target?: Session;
	problem?: string;
}

const NO_PLAYTEST =
	"no playtest is running, so there's no live game to run this in. Start one with the playtest " +
	"tool, or use run_timeline, which starts and stops its own.";

export function routeFor(plugin: Session, args: Record<string, unknown>): Routed {
	const context = args.context;
	if (context === undefined || context === "plugin" || context === "edit") {
		return { target: plugin };
	}

	if (context === "server") {
		const server = plugin.peers.server;
		if (!server?.isOpen) return { problem: NO_PLAYTEST };
		return { target: server };
	}

	if (context === "client") {
		const clients = plugin.peers.clients.filter((peer) => peer.isOpen);
		if (clients.length === 0) return { problem: NO_PLAYTEST };

		const asked = typeof args.player === "number" ? args.player : 1;
		const client = clients[asked - 1];
		if (!client) {
			return { problem: `asked for client ${asked}, but this playtest has ${clients.length}` };
		}
		return { target: client };
	}

	return { problem: `context must be plugin, server or client — got "${String(context)}"` };
}

/** The edit session behind any session, which is where tool names and peers both live. */
export function ownerOf(session: Session, lookup: (id: string) => Session | undefined): Session | undefined {
	if (session.role === "plugin") return session;
	return session.linkId ? lookup(session.linkId) : undefined;
}
