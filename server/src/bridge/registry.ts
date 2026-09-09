import { EventEmitter } from "node:events";
import { config, log } from "../config.js";
import type { Manifest } from "../manifest.js";
import type { ToolDefinition } from "../protocol.js";
import { Session } from "./session.js";

export interface ExposedTool {
	/** The name the MCP client sees — bare, or place-prefixed when 2+ places are known. */
	exposedName: string;
	placeId: string;
	placeName: string;
	online: boolean;
	/** Present only while the place is connected. */
	session?: Session;
	tool: ToolDefinition;
}

interface Contributor {
	placeId: string;
	placeName: string;
	tools: ToolDefinition[];
	/** Distinguishes two Studio windows showing the same place. */
	discriminator: string;
	session?: Session;
}

const MAX_PREFIX = 24;

function sanitize(placeName: string): string {
	const cleaned = placeName.replace(/[^A-Za-z0-9_]/g, "_").replace(/_+/g, "_").replace(/^_|_$/g, "");
	return (cleaned || "place").slice(0, MAX_PREFIX);
}

/**
 * Live sessions keyed by sessionId — one per Studio window, so the same place open
 * twice is two sessions — merged with the disk manifest so tools stay listed while
 * their place is closed. Emits "changed" whenever the exposed list shifts.
 */
export class SessionRegistry extends EventEmitter {
	private readonly sessions = new Map<string, Session>();
	private exposed = new Map<string, ExposedTool>();

	constructor(private readonly manifest: Manifest) {
		super();
		this.rebuild();
	}

	add(session: Session): void {
		// A plugin reload can leave the old socket alive; evict it so it doesn't hold names.
		const previous = this.sessions.get(session.sessionId);
		if (previous) {
			previous.dispose(`replaced by a new connection from ${session.placeName}`);
			previous.closeSocket();
		}

		this.sessions.set(session.sessionId, session);
		this.manifest.record(session.placeId, session.placeName, session.tools);
		log(`${session.placeName} connected with ${session.tools.length} tool(s)`);
		this.rebuild();
	}

	remove(session: Session): void {
		if (this.sessions.get(session.sessionId) !== session) return;
		this.sessions.delete(session.sessionId);
		log(`${session.placeName} disconnected`);
		this.rebuild();
	}

	updateTools(session: Session, tools: ToolDefinition[]): void {
		session.tools = tools;
		this.manifest.record(session.placeId, session.placeName, tools);
		log(`${session.placeName} re-registered ${tools.length} tool(s)`);
		this.rebuild();
	}

	list(): ExposedTool[] {
		return [...this.exposed.values()];
	}

	resolve(exposedName: string): ExposedTool | undefined {
		return this.exposed.get(exposedName);
	}

	private contributors(): Contributor[] {
		const live: Contributor[] = [...this.sessions.values()].map((session) => ({
			placeId: session.placeId,
			placeName: session.placeName,
			tools: session.tools,
			discriminator: session.sessionId,
			session,
		}));

		if (!config.listOfflineTools) return live;

		const connectedPlaces = new Set(live.map((entry) => entry.placeId));
		const offline: Contributor[] = [];
		for (const [placeId, entry] of this.manifest.all()) {
			if (connectedPlaces.has(placeId)) continue;
			offline.push({
				placeId,
				placeName: entry.placeName,
				tools: entry.tools,
				discriminator: placeId,
			});
		}

		return [...live, ...offline];
	}

	private rebuild(): void {
		const contributors = this.contributors();
		const prefixes = this.assignPrefixes(contributors);
		const next = new Map<string, ExposedTool>();

		for (const [index, contributor] of contributors.entries()) {
			const prefix = prefixes[index];
			for (const tool of contributor.tools) {
				const exposedName = prefix ? `${prefix}__${tool.name}` : tool.name;
				const exposed: ExposedTool = {
					exposedName,
					placeId: contributor.placeId,
					placeName: contributor.placeName,
					online: contributor.session !== undefined,
					tool,
				};
				if (contributor.session) exposed.session = contributor.session;
				next.set(exposedName, exposed);
			}
		}

		const changed = !sameListing(this.exposed, next);
		this.exposed = next;
		if (changed) this.emit("changed");
	}

	/** One contributor means bare names. Two or more means everything is namespaced. */
	private assignPrefixes(contributors: Contributor[]): (string | undefined)[] {
		if (contributors.length < 2) return contributors.map(() => undefined);

		const counts = new Map<string, number>();
		for (const contributor of contributors) {
			const base = sanitize(contributor.placeName);
			counts.set(base, (counts.get(base) ?? 0) + 1);
		}

		// Two windows on one place, or two places sharing a name, both land here.
		return contributors.map((contributor) => {
			const base = sanitize(contributor.placeName);
			return (counts.get(base) ?? 0) > 1 ? `${base}_${contributor.discriminator.slice(-4)}` : base;
		});
	}
}

function sameListing(a: Map<string, ExposedTool>, b: Map<string, ExposedTool>): boolean {
	if (a.size !== b.size) return false;
	for (const [name, tool] of a) {
		const other = b.get(name);
		if (!other || other.online !== tool.online || other.tool !== tool.tool) return false;
	}
	return true;
}
