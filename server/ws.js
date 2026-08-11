// ============================================================================
// server/ws.js — минимальный WebSocket-сервер (RFC 6455) без зависимостей.
//
// Проект позиционируется как «без зависимостей», поэтому вместо пакета ws
// здесь компактная реализация: рукопожатие (handshake) + фреймы + ping/pong.
// Поддерживаются текстовые сообщения; фрагментация конкатенируется.
// ============================================================================

import { createHash } from 'node:crypto';

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const OP = {
  CONTINUATION: 0x0,
  TEXT: 0x1,
  BINARY: 0x2,
  CLOSE: 0x8,
  PING: 0x9,
  PONG: 0xa,
};

/**
 * Обёртка над одним сокетом: буфер входящих байт, очередь исходящих фреймов.
 */
class Connection {
  constructor(socket) {
    this.socket = socket;
    this.buf = Buffer.alloc(0);
    this.fragments = [];
    this.closed = false;
    this.onmessage = null;
    this.onclose = null;
    this.onerror = null;
    this.readyState = 0; // CONNECTING, затем OPEN(1)
    this._out = [];
    socket.on('data', (chunk) => this.#onData(chunk));
    socket.on('error', (e) => this.onerror?.(e));
    socket.on('close', () => this.#close());
    socket.on('end', () => this.#close());
  }

  send(text) {
    if (this.closed || this.readyState !== 1) return;
    const payload = Buffer.from(text, 'utf8');
    const header = this.#frameHeader(OP.TEXT, payload.length, false);
    this.socket.write(Buffer.concat([header, payload]));
  }

  close() {
    if (this.closed) return;
    this.socket.write(this.#frameHeader(OP.CLOSE, 0, false));
    this.socket.end();
  }

  #close() {
    if (this.closed) return;
    this.closed = true;
    this.readyState = 3;
    this.onclose?.();
  }

  #onData(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    while (true) {
      const frame = this.#parseFrame();
      if (!frame) break;
      this.#handleFrame(frame);
    }
  }

  /** Пытается разобрать один фрейм из начала буфера. null — данных мало. */
  #parseFrame() {
    const b = this.buf;
    if (b.length < 2) return null;
    const fin = (b[0] & 0x80) !== 0;
    const opcode = b[0] & 0x0f;
    const masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7f;
    let offset = 2;
    if (len === 126) {
      if (b.length < offset + 2) return null;
      len = b.readUInt16BE(offset);
      offset += 2;
    } else if (len === 127) {
      if (b.length < offset + 8) return null;
      len = Number(b.readBigUInt64BE(offset));
      offset += 8;
    }
    let maskKey = null;
    if (masked) {
      if (b.length < offset + 4) return null;
      maskKey = b.subarray(offset, offset + 4);
      offset += 4;
    }
    if (b.length < offset + len) return null;
    let payload = b.subarray(offset, offset + len);
    if (masked) {
      payload = Buffer.from(payload);
      for (let i = 0; i < payload.length; i++) payload[i] ^= maskKey[i & 3];
    }
    this.buf = b.subarray(offset + len);
    return { fin, opcode, payload };
  }

  #handleFrame(frame) {
    switch (frame.opcode) {
      case OP.CLOSE:
        this.close();
        break;
      case OP.PING:
        this.socket.write(this.#frameHeader(OP.PONG, 0, false));
        break;
      case OP.TEXT:
      case OP.BINARY:
        this.fragments.push(frame.payload);
        if (frame.fin) {
          const data = Buffer.concat(this.fragments);
          this.fragments = [];
          this.onmessage?.(data.toString('utf8'));
        }
        break;
      case OP.CONTINUATION:
        this.fragments.push(frame.payload);
        if (frame.fin) {
          const data = Buffer.concat(this.fragments);
          this.fragments = [];
          this.onmessage?.(data.toString('utf8'));
        }
        break;
      default:
        break; // PONG и неизвестные — игнорируем
    }
  }

  #frameHeader(opcode, len, masked) {
    const h = Buffer.alloc(10);
    let offset = 0;
    h[0] = 0x80 | opcode;
    if (len < 126) {
      h[1] = len;
      offset = 2;
    } else if (len < 65536) {
      h[1] = 126;
      h.writeUInt16BE(len, 2);
      offset = 4;
    } else {
      h[1] = 127;
      h.writeBigUInt64BE(BigInt(len), 2);
      offset = 10;
    }
    return h.subarray(0, offset);
  }
}

/**
 * Минимальный WebSocket-сервер поверх http.
 * @param {import('node:http').Server} httpServer
 * @param {(conn: Connection) => void} [onConnection]
 */
export function attachWebSocket(httpServer, onConnection = null) {
  const connections = new Set();
  httpServer.on('upgrade', (req, socket) => {
    const key = req.headers['sec-websocket-key'];
    if (!key) {
      socket.destroy();
      return;
    }
    const accept = createHash('sha1').update(key + GUID).digest('base64');
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n' +
        'Upgrade: websocket\r\n' +
        'Connection: Upgrade\r\n' +
        `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
    );
    const conn = new Connection(socket);
    conn.readyState = 1;
    connections.add(conn);
    conn.onclose = () => {
      connections.delete(conn);
    };
    onConnection?.(conn);
  });
  return {
    connections,
  };
}
