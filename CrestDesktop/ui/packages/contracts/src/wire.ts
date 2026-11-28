/**
 * The positional contract wire format, read and written exactly as the core's
 * `WireReader` and `WireWriter` (CrestCore/src/CrestCore.Native/Wire) do:
 * varints for tags, counts, presence-free enums and lengths; little-endian
 * fixed-width numbers; UTF-8 strings after their byte length; GUIDs as their
 * 16 big-endian bytes; dates as seconds from 2001-01-01 UTC.
 */

/** 2001-01-01T00:00:00Z, the reference date dates count seconds from. */
const referenceMilliseconds = Date.UTC(2001, 0, 1);

export class WireFormatError extends Error {}

export class WireReader {
  #view: DataView;
  #bytes: Uint8Array;
  #offset = 0;

  constructor(bytes: Uint8Array) {
    this.#bytes = bytes;
    this.#view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }

  get remaining(): number {
    return this.#bytes.byteLength - this.#offset;
  }

  ensureEnd(): void {
    if (this.remaining !== 0) throw new WireFormatError(`${this.remaining} unexpected trailing bytes.`);
  }

  readTag(): number {
    return this.#bounded(0x7fffffff, "tag");
  }

  readCount(): number {
    const count = this.#bounded(0x7fffffff, "count");
    if (count > this.remaining * 8 + 1024) throw new WireFormatError(`A count of ${count} exceeds the message.`);
    return count;
  }

  readPresence(): boolean {
    return this.#flag("presence");
  }

  readEnum(count: number): number {
    return this.#bounded(count - 1, "enum");
  }

  readFlags(mask: number): number {
    const value = this.#bounded(0x7fffffff, "flags");
    if ((value & ~mask) !== 0) throw new WireFormatError(`Unknown flags ${value}.`);
    return value;
  }

  readList<T>(element: () => T): T[] {
    const count = this.readCount();
    const items = new Array<T>(count);
    for (let index = 0; index < count; index++) items[index] = element();
    return items;
  }

  readBool(): boolean {
    return this.#flag("bool");
  }

  readInt32(): number {
    const value = this.#view.getInt32(this.#take(4), true);
    return value;
  }

  readInt64(): bigint {
    return this.#view.getBigInt64(this.#take(8), true);
  }

  readUInt64(): bigint {
    return this.#view.getBigUint64(this.#take(8), true);
  }

  readDouble(): number {
    return this.#view.getFloat64(this.#take(8), true);
  }

  readString(): string {
    const length = this.readCount();
    const start = this.#take(length);
    return utf8Decoder.decode(this.#bytes.subarray(start, start + length));
  }

  readBytes(): Uint8Array {
    const length = this.readCount();
    const start = this.#take(length);
    return this.#bytes.slice(start, start + length);
  }

  readGuid(): string {
    const start = this.#take(16);
    const hex = Array.from(this.#bytes.subarray(start, start + 16), (byte) => byte.toString(16).padStart(2, "0")).join("");
    return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
  }

  readDate(): Date {
    const seconds = this.readDouble();
    if (!Number.isFinite(seconds)) throw new WireFormatError(`A date of ${seconds} seconds is out of range.`);
    return new Date(referenceMilliseconds + seconds * 1000);
  }

  readDuration(): number {
    const seconds = this.readDouble();
    if (!Number.isFinite(seconds)) throw new WireFormatError(`A duration of ${seconds} seconds is out of range.`);
    return seconds;
  }

  #take(count: number): number {
    if (count > this.remaining) throw new WireFormatError(`Needed ${count} bytes, ${this.remaining} remain.`);
    const start = this.#offset;
    this.#offset += count;
    return start;
  }

  #flag(what: string): boolean {
    const byte = this.#bytes[this.#take(1)];
    if (byte === 0) return false;
    if (byte === 1) return true;
    throw new WireFormatError(`A ${what} byte of ${byte}.`);
  }

  /** A varint no larger than `maximum`, which must fit a 31-bit integer. */
  #bounded(maximum: number, what: string): number {
    let value = 0;
    let shift = 0;
    for (;;) {
      const byte = this.#bytes[this.#take(1)];
      value += (byte & 0x7f) * 2 ** shift;
      if ((byte & 0x80) === 0) break;
      shift += 7;
      if (shift > 35) throw new WireFormatError(`An overlong ${what}.`);
    }
    if (value > maximum) throw new WireFormatError(`A ${what} of ${value} exceeds ${maximum}.`);
    return value;
  }
}

export class WireWriter {
  #bytes = new Uint8Array(256);
  #view = new DataView(this.#bytes.buffer);
  #length = 0;

  /** What was written. */
  toBytes(): Uint8Array {
    return this.#bytes.slice(0, this.#length);
  }

  writeTag(tag: number): void {
    this.writeVarint(tag);
  }

  writeCount(count: number): void {
    this.writeVarint(count);
  }

  writePresence(isPresent: boolean): void {
    this.writeBool(isPresent);
  }

  writeEnum(value: number): void {
    this.writeVarint(value);
  }

  writeVarint(value: number): void {
    if (!Number.isSafeInteger(value) || value < 0) throw new RangeError(`Cannot write ${value} as a varint.`);
    this.#reserve(10);
    do {
      const next = value % 128;
      value = Math.floor(value / 128);
      this.#bytes[this.#length++] = value === 0 ? next : next | 0x80;
    } while (value !== 0);
  }

  writeBool(value: boolean): void {
    this.#reserve(1);
    this.#bytes[this.#length++] = value ? 1 : 0;
  }

  // Each write takes its offset before it reads the buffer: taking the offset
  // may grow the buffer, and the write must land in the grown one.

  writeInt32(value: number): void {
    const start = this.#advance(4);
    this.#view.setInt32(start, value, true);
  }

  writeInt64(value: bigint): void {
    const start = this.#advance(8);
    this.#view.setBigInt64(start, value, true);
  }

  writeUInt64(value: bigint): void {
    const start = this.#advance(8);
    this.#view.setBigUint64(start, value, true);
  }

  writeDouble(value: number): void {
    const start = this.#advance(8);
    this.#view.setFloat64(start, value, true);
  }

  writeString(value: string): void {
    const encoded = utf8Encoder.encode(value);
    this.writeCount(encoded.byteLength);
    const start = this.#advance(encoded.byteLength);
    this.#bytes.set(encoded, start);
  }

  writeBytes(value: Uint8Array): void {
    this.writeCount(value.byteLength);
    const start = this.#advance(value.byteLength);
    this.#bytes.set(value, start);
  }

  writeGuid(value: string): void {
    const hex = value.replaceAll("-", "");
    if (!/^[0-9a-fA-F]{32}$/.test(hex)) throw new RangeError(`${value} is not a GUID.`);
    const start = this.#advance(16);
    for (let index = 0; index < 16; index++) this.#bytes[start + index] = parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }

  writeDate(value: Date): void {
    this.writeDouble((value.getTime() - referenceMilliseconds) / 1000);
  }

  writeDuration(seconds: number): void {
    this.writeDouble(seconds);
  }

  #advance(count: number): number {
    this.#reserve(count);
    const start = this.#length;
    this.#length += count;
    return start;
  }

  #reserve(count: number): void {
    if (this.#length + count <= this.#bytes.byteLength) return;
    let capacity = this.#bytes.byteLength * 2;
    while (capacity < this.#length + count) capacity *= 2;
    const grown = new Uint8Array(capacity);
    grown.set(this.#bytes.subarray(0, this.#length));
    this.#bytes = grown;
    this.#view = new DataView(grown.buffer);
  }
}

const utf8Encoder = new TextEncoder();
// A leading U+FEFF is part of the string the core wrote, not a byte order mark.
const utf8Decoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
