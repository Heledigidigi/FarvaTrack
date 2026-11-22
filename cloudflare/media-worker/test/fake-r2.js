// Testler için bellek içi R2 kovası (Worker'ın kullandığı yöntemler kadar).

async function toBytes(body) {
  if (body == null) return new Uint8Array(0);
  if (body instanceof Uint8Array) return body;
  return new Uint8Array(await new Response(body).arrayBuffer());
}

export class FakeBucket {
  constructor() {
    this.objects = new Map();
    this.uploads = new Map();
    this.clock = () => new Date();
  }

  meta(key, entry) {
    return {
      key,
      size: entry.bytes.length,
      uploaded: entry.uploaded,
      httpEtag: `"${key.length}-${entry.bytes.length}"`,
      customMetadata: entry.customMetadata || {},
      writeHttpMetadata(headers) {
        if (entry.httpMetadata?.contentType) headers.set('content-type', entry.httpMetadata.contentType);
      },
    };
  }

  async put(key, body, options = {}) {
    const bytes = await toBytes(body);
    this.objects.set(key, { bytes, uploaded: this.clock(), httpMetadata: options.httpMetadata, customMetadata: options.customMetadata });
    return this.meta(key, this.objects.get(key));
  }

  async head(key) {
    const entry = this.objects.get(key);
    return entry ? this.meta(key, entry) : null;
  }

  async get(key, options = {}) {
    const entry = this.objects.get(key);
    if (!entry) return null;
    const meta = this.meta(key, entry);
    let bytes = entry.bytes;
    const header = options.range?.get?.('range');
    let range;
    if (header) {
      const [, start, end] = header.match(/bytes=(\d+)-(\d*)/);
      const offset = Number(start);
      const last = end ? Number(end) : bytes.length - 1;
      range = { offset, length: last - offset + 1 };
      bytes = bytes.slice(offset, last + 1);
    }
    return { ...meta, range, body: new Response(bytes).body };
  }

  async delete(keys) {
    for (const key of Array.isArray(keys) ? keys : [keys]) this.objects.delete(key);
  }

  async list({ prefix = '', cursor, limit = 1000 } = {}) {
    const keys = [...this.objects.keys()].filter((k) => k.startsWith(prefix)).sort();
    const start = cursor ? Number(cursor) : 0;
    const page = keys.slice(start, start + limit);
    return {
      objects: page.map((k) => this.meta(k, this.objects.get(k))),
      truncated: start + limit < keys.length,
      cursor: String(start + limit),
    };
  }

  async createMultipartUpload(key, options) {
    const uploadId = `up-${this.uploads.size + 1}`;
    this.uploads.set(uploadId, { key, options, parts: new Map() });
    return { uploadId };
  }

  resumeMultipartUpload(key, uploadId) {
    const bucket = this;
    return {
      async uploadPart(partNumber, body) {
        const upload = bucket.uploads.get(uploadId);
        if (!upload || upload.key !== key) throw new Error('yükleme yok');
        upload.parts.set(partNumber, await toBytes(body));
        return { partNumber, etag: `e${partNumber}` };
      },
      async complete(parts) {
        const upload = bucket.uploads.get(uploadId);
        const chunks = parts.map((p) => upload.parts.get(p.partNumber));
        const total = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
        let offset = 0;
        for (const c of chunks) { total.set(c, offset); offset += c.length; }
        bucket.uploads.delete(uploadId);
        return bucket.put(key, total, upload.options);
      },
      async abort() { bucket.uploads.delete(uploadId); },
    };
  }
}
