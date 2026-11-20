/**
 * How the interface reaches the native core. The core's C ABI is synchronous;
 * from a page every call is a message to the browser process, so each answers
 * asynchronously with the status and bytes the C call returned. The bytes are
 * the contract wire format, which only the interface reads.
 */
export interface CoreReply {
  readonly status: number;
  readonly bytes: Uint8Array;
}

export interface CoreTransport {
  create(fingerprint: Uint8Array, configuration: Uint8Array): Promise<CoreReply>;
  dispatch(intent: Uint8Array): Promise<CoreReply>;
  query(query: Uint8Array): Promise<CoreReply>;
  drain(): Promise<CoreReply>;
  endTurn(): Promise<CoreReply>;
  registerEngine(fingerprint: Uint8Array, registration: Uint8Array): Promise<CoreReply>;
  report(engine: bigint, event: Uint8Array): Promise<CoreReply>;
  ask(engine: bigint, question: Uint8Array): Promise<CoreReply>;
  /** A page request to the page's engine binding directly, where the host carries one. */
  request?(request: Uint8Array): Promise<CoreReply>;
  /** The batch a wake drained: what the core changed on its own. */
  onChanges?: (reply: CoreReply) => void;
  /** A command the core issued to an engine the interface registered. */
  onCommand?: (engine: bigint, command: Uint8Array) => void;
}

/** `crest_status_t` values the interface acts on (crest_core.h, crest_app.h). */
export const CoreStatus = Object.freeze({ ok: 0, rejected: 6 });

const enum Op {
  Create = 1,
  Dispatch,
  Query,
  Drain,
  EndTurn,
  RegisterEngine,
  Report,
  Ask,
}

const changesPush = 0xf0;
const commandPush = 0xf1;

/**
 * The development bridge (CrestDesktop/devhost): the native core in a local
 * process, reached over a WebSocket, so the interface runs in any browser.
 */
export class DevSocketTransport implements CoreTransport {
  onChanges?: (reply: CoreReply) => void;
  onCommand?: (engine: bigint, command: Uint8Array) => void;

  #socket: WebSocket;
  #opened: Promise<void>;
  #nextId = 1;
  #pending = new Map<number, (reply: CoreReply) => void>();

  constructor(url: string) {
    this.#socket = new WebSocket(url);
    this.#socket.binaryType = "arraybuffer";
    this.#opened = new Promise((resolve, reject) => {
      this.#socket.addEventListener("open", () => resolve(), { once: true });
      this.#socket.addEventListener("error", () => reject(new Error(`Cannot reach the core bridge at ${url}`)), { once: true });
    });
    this.#socket.addEventListener("message", (event) => this.#receive(new Uint8Array(event.data as ArrayBuffer)));
  }

  create(fingerprint: Uint8Array, configuration: Uint8Array) {
    const prefix = new Uint8Array(4);
    new DataView(prefix.buffer).setUint32(0, fingerprint.byteLength, true);
    return this.#request(Op.Create, prefix, fingerprint, configuration);
  }

  dispatch(intent: Uint8Array) {
    return this.#request(Op.Dispatch, intent);
  }

  query(query: Uint8Array) {
    return this.#request(Op.Query, query);
  }

  drain() {
    return this.#request(Op.Drain);
  }

  endTurn() {
    return this.#request(Op.EndTurn);
  }

  registerEngine(fingerprint: Uint8Array, registration: Uint8Array) {
    const prefix = new Uint8Array(4);
    new DataView(prefix.buffer).setUint32(0, fingerprint.byteLength, true);
    return this.#request(Op.RegisterEngine, prefix, fingerprint, registration);
  }

  report(engine: bigint, event: Uint8Array) {
    return this.#request(Op.Report, handle(engine), event);
  }

  ask(engine: bigint, question: Uint8Array) {
    return this.#request(Op.Ask, handle(engine), question);
  }

  async #request(op: Op, ...parts: Uint8Array[]): Promise<CoreReply> {
    await this.#opened;
    const id = this.#nextId++;
    const length = parts.reduce((total, part) => total + part.byteLength, 5);
    const frame = new Uint8Array(length);
    frame[0] = op;
    new DataView(frame.buffer).setUint32(1, id, true);
    let offset = 5;
    for (const part of parts) {
      frame.set(part, offset);
      offset += part.byteLength;
    }
    return new Promise((resolve) => {
      this.#pending.set(id, resolve);
      this.#socket.send(frame);
    });
  }

  #receive(frame: Uint8Array) {
    const view = new DataView(frame.buffer, frame.byteOffset, frame.byteLength);
    if (frame[0] === changesPush) {
      this.onChanges?.({ status: view.getInt32(1, true), bytes: frame.subarray(5) });
    } else if (frame[0] === commandPush) {
      this.onCommand?.(view.getBigUint64(1, true), frame.subarray(9));
    } else {
      const id = view.getUint32(1, true);
      const resolve = this.#pending.get(id);
      this.#pending.delete(id);
      resolve?.({ status: view.getInt32(5, true), bytes: frame.subarray(9) });
    }
  }
}

function handle(engine: bigint): Uint8Array {
  const bytes = new Uint8Array(8);
  new DataView(bytes.buffer).setBigUint64(0, engine, true);
  return bytes;
}
