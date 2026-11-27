import {
  type AnswerOfPageRequest,
  type AnswerOfQuery,
  type PageRequest,
  readPageRequestAnswer,
  writePageRequest,
  type AppConfiguration,
  type Change,
  type EngineCommand,
  type EngineEvent,
  type EngineRegistration,
  type Intent,
  type Query,
  type Rejection,
  WireReader,
  WireWriter,
  engineFingerprint,
  fingerprint,
  readChange,
  readEngineCommand,
  readQueryAnswer,
  readRejection,
  writeAppConfiguration,
  writeEngineEvent,
  writeEngineRegistration,
  writeIntent,
  writeQuery,
} from "@crest/contracts";

import { CoreState } from "./core-state";
import { type CoreReply, CoreStatus, type CoreTransport } from "./transport";

/** The rule the core refused an intent or a query with. */
export class CoreRejection extends Error {
  constructor(readonly rejection: Rejection) {
    super(`The core refused it: ${rejection.$kind}`);
  }
}

/** A status that is neither OK nor a rejection: a caller or build bug (crest_app.h). */
export class CoreFailure extends Error {
  constructor(readonly status: number, what: string) {
    super(`${what} failed with core status ${status}`);
  }
}

/** An engine binding the interface runs: it receives the core's commands for its pages. */
export interface EngineBindingHandler {
  run(command: EngineCommand, engine: RegisteredEngine): void;
}

/** An engine registered with the core, which reports what happens to its pages. */
export class RegisteredEngine {
  constructor(readonly handle: bigint, readonly core: CrestCore) {}

  report(event: EngineEvent): Promise<void> {
    return this.core.report(this, event);
  }
}

/**
 * The interface's core: it sends intents and asks queries, and keeps the read
 * model current with every change the core publishes, those an intent answers
 * with and those the core starts itself.
 */
export class CrestCore {
  readonly state = new CoreState();

  #transport: CoreTransport;
  #engines = new Map<bigint, { engine: RegisteredEngine; handler: EngineBindingHandler }>();

  private constructor(transport: CoreTransport) {
    this.#transport = transport;
    transport.onChanges = (reply) => this.#applyBatch(reply, "Drain");
    transport.onCommand = (handle, bytes) => {
      const registered = this.#engines.get(handle);
      if (!registered) return;
      const reader = new WireReader(bytes);
      registered.handler.run(readEngineCommand(reader), registered.engine);
    };
  }

  static async start(transport: CoreTransport, configuration: AppConfiguration): Promise<CrestCore> {
    const core = new CrestCore(transport);
    const writer = new WireWriter();
    writeAppConfiguration(writer, configuration);
    const reply = await transport.create(fingerprint, writer.toBytes());
    if (reply.status === CoreStatus.rejected) throw new CoreRejection(readRejection(new WireReader(reply.bytes)));
    if (reply.status !== CoreStatus.ok) throw new CoreFailure(reply.status, "Creating the core");
    return core;
  }

  /** Sends an intent and answers the changes it published, which the read model already holds. */
  async send(intent: Intent): Promise<readonly Change[]> {
    const writer = new WireWriter();
    writeIntent(writer, intent);
    return this.#applyBatch(await this.#transport.dispatch(writer.toBytes()), intent.$kind);
  }

  async query<Q extends Query>(question: Q): Promise<AnswerOfQuery<Q>> {
    const writer = new WireWriter();
    writeQuery(writer, question);
    const reply = await this.#transport.query(writer.toBytes());
    if (reply.status === CoreStatus.rejected) throw new CoreRejection(readRejection(new WireReader(reply.bytes)));
    if (reply.status !== CoreStatus.ok) throw new CoreFailure(reply.status, question.$kind);
    return readQueryAnswer(question, new WireReader(reply.bytes));
  }

  /**
   * Asks a page's engine for view work directly, as `EnginePage` does on the
   * Mac: reload, find, zoom, the page's icon. The core never sees it.
   */
  async request<R extends PageRequest>(request: R): Promise<AnswerOfPageRequest<R>> {
    if (!this.#transport.request) throw new CoreFailure(-1, `${request.$kind}: this host has no direct path to pages`);
    const writer = new WireWriter();
    writePageRequest(writer, request);
    const reply = await this.#transport.request(writer.toBytes());
    if (reply.status !== CoreStatus.ok) throw new CoreFailure(reply.status, request.$kind);
    return readPageRequestAnswer(request, new WireReader(reply.bytes));
  }

  async registerEngine(registration: EngineRegistration, handler: EngineBindingHandler): Promise<RegisteredEngine> {
    const writer = new WireWriter();
    writeEngineRegistration(writer, registration);
    const reply = await this.#transport.registerEngine(engineFingerprint, writer.toBytes());
    if (reply.status === CoreStatus.rejected) throw new CoreRejection(readRejection(new WireReader(reply.bytes)));
    if (reply.status !== CoreStatus.ok) throw new CoreFailure(reply.status, "Registering an engine");
    const handle = new DataView(reply.bytes.buffer, reply.bytes.byteOffset).getBigUint64(0, true);
    const engine = new RegisteredEngine(handle, this);
    this.#engines.set(handle, { engine, handler });
    return engine;
  }

  /**
   * Registers the engine the host carries, Chromium's binding in Crest's own
   * Chromium, which receives the core's commands and reports by itself.
   */
  async registerNativeEngine(registration: EngineRegistration): Promise<void> {
    const writer = new WireWriter();
    writeEngineRegistration(writer, registration);
    const reply = await this.#transport.registerEngine(engineFingerprint, writer.toBytes());
    if (reply.status === CoreStatus.rejected) throw new CoreRejection(readRejection(new WireReader(reply.bytes)));
    if (reply.status !== CoreStatus.ok) throw new CoreFailure(reply.status, "Registering the native engine");
  }

  async report(engine: RegisteredEngine, event: EngineEvent): Promise<void> {
    const writer = new WireWriter();
    writeEngineEvent(writer, event);
    const reply = await this.#transport.report(engine.handle, writer.toBytes());
    if (reply.status !== CoreStatus.ok) throw new CoreFailure(reply.status, event.$kind);
    // What the report changed waits for the next drain.
    this.#applyBatch(await this.#transport.drain(), "Drain");
    await this.#transport.endTurn();
  }

  #applyBatch(reply: CoreReply, what: string): readonly Change[] {
    if (reply.status === CoreStatus.rejected) throw new CoreRejection(readRejection(new WireReader(reply.bytes)));
    if (reply.status !== CoreStatus.ok) throw new CoreFailure(reply.status, what);
    const reader = new WireReader(reply.bytes);
    const changes = reader.readList(() => readChange(reader));
    reader.ensureEnd();
    this.state.apply(changes);
    return changes;
  }
}
