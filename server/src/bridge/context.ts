/**
 * The context a timeline's events share.
 *
 * It lives here, on the server, because there is nowhere else it could. The edit DataModel, the
 * test server and each test client are separate processes running separate copies of the plugin;
 * the socket back to VMCP is the only thing all of them can touch. That also makes this the one
 * place that sees every write, so the ordering it records is the real one.
 */

export interface ContextWrite {
	at: number;
	from: string;
	key: string;
}

const MAX_WRITES = 500;
const MAX_NOTES = 300;

export class SharedContext {
	private values = new Map<string, unknown>();
	private writes: ContextWrite[] = [];
	private notes: string[] = [];

	set(key: string, value: unknown, from: string, at: number): void {
		this.values.set(key, value);
		if (this.writes.length < MAX_WRITES) {
			this.writes.push({ key, from, at: Number.isFinite(at) ? at : Date.now() / 1000 });
		}
	}

	get(key: string): unknown {
		return this.values.get(key);
	}

	note(text: string): void {
		if (this.notes.length < MAX_NOTES) this.notes.push(text);
	}

	clear(): void {
		this.values.clear();
		this.writes = [];
		this.notes = [];
	}

	snapshot(): { values: Record<string, unknown>; writes: ContextWrite[]; notes: string[] } {
		return {
			values: Object.fromEntries(this.values),
			// Sorted by the stamp each context took at the moment it wrote, so a client's write that
			// arrived late still reads in the order it actually happened.
			writes: [...this.writes].sort((a, b) => a.at - b.at),
			notes: [...this.notes],
		};
	}
}
