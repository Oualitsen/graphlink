const expressRestSupportFileName = 'support.ts';

const expressRestSupport = r'''import { NextFunction, Request, RequestHandler, Response } from 'express';

export class RestError extends Error {
   constructor(readonly status: number, message: string) {
      super(message);
   }
}

export type Shape =
   | { k: 'string' | 'int' | 'float' | 'boolean' | 'any' }
   | { k: 'enum'; values: string[] }
   | { k: 'list'; of: Shape; nullable: boolean }
   | { k: 'ref'; name: string }
   | { k: 'object'; fields: Record<string, { shape: Shape; required: boolean }> };

export type Shapes = Record<string, Shape>;

export const S: Record<'string' | 'int' | 'float' | 'boolean', Shape> = {
   string: { k: 'string' },
   int: { k: 'int' },
   float: { k: 'float' },
   boolean: { k: 'boolean' },
};

const intMin = -2147483648;
const intMax = 2147483647;
const reasons: Record<number, string> = {
   400: 'Bad Request',
   404: 'Not Found',
   405: 'Method Not Allowed',
   413: 'Payload Too Large',
   415: 'Unsupported Media Type',
   500: 'Internal Server Error',
};

function bad(message: string): never {
   throw new RestError(400, message);
}

function isInt(value: unknown): value is number {
   return typeof value === 'number' && Number.isInteger(value) && value >= intMin && value <= intMax;
}

export function parseScalar(text: string, shape: Shape): unknown {
   switch (shape.k) {
      case 'int':
         if (!/^-?\d+$/.test(text) || !isInt(Number(text))) bad('Invalid integer');
         return Number(text);
      case 'float':
         if (!/^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(text) || !Number.isFinite(Number(text))) bad('Invalid number');
         return Number(text);
      case 'boolean':
         if (text !== 'true' && text !== 'false') bad('Invalid boolean');
         return text === 'true';
      case 'enum':
         if (!shape.values.includes(text)) bad('Invalid enum value');
         return text;
      default:
         return text;
   }
}

export function validate(value: unknown, shape: Shape, shapes: Shapes): void {
   switch (shape.k) {
      case 'ref':
         return validate(value, shapes[shape.name], shapes);
      case 'string':
         if (typeof value !== 'string') bad('Expected a string');
         return;
      case 'int':
         if (!isInt(value)) bad('Expected an integer');
         return;
      case 'float':
         if (typeof value !== 'number' || !Number.isFinite(value)) bad('Expected a number');
         return;
      case 'boolean':
         if (typeof value !== 'boolean') bad('Expected a boolean');
         return;
      case 'enum':
         if (typeof value !== 'string' || !shape.values.includes(value)) bad('Invalid enum value');
         return;
      case 'any':
         return;
      case 'list':
         if (!Array.isArray(value)) bad('Expected a list');
         for (const item of value as unknown[]) {
            if (item == null) {
               if (!shape.nullable) bad('Null list element');
            } else {
               validate(item, shape.of, shapes);
            }
         }
         return;
      case 'object': {
         if (value === null || typeof value !== 'object' || Array.isArray(value)) bad('Expected an object');
         const fields = value as Record<string, unknown>;
         for (const [name, field] of Object.entries(shape.fields)) {
            const present = fields[name];
            if (present == null) {
               if (field.required) bad(`Missing field ${name}`);
            } else {
               validate(present, field.shape, shapes);
            }
         }
         return;
      }
   }
}

export interface ArgOptions {
   optional?: boolean;
   defaultValue?: unknown;
}

function absent(name: string, options: ArgOptions): unknown {
   if (options.defaultValue !== undefined) return options.defaultValue;
   if (options.optional) return null;
   return bad(`Missing ${name}`);
}

function splitList(values: string[]): string[] {
   return values.flatMap((value) => value.split(','));
}

function queryValues(req: Request, name: string): string[] {
   const query = req.originalUrl.split('?')[1] ?? '';
   return new URLSearchParams(query).getAll(name);
}

function headerValues(req: Request, name: string): string[] {
   const value = req.get(name);
   return value === undefined ? [] : [value];
}

export function pathArg(req: Request, name: string, shape: Shape): any {
   return parseScalar(req.params[name], shape);
}

export function queryArg(req: Request, name: string, shape: Shape, options: ArgOptions = {}): any {
   const values = queryValues(req, name);
   return values.length === 0 ? absent(name, options) : parseScalar(values[0], shape);
}

export function queryListArg(req: Request, name: string, element: Shape, options: ArgOptions = {}): any {
   const values = queryValues(req, name);
   return values.length === 0 ? absent(name, options) : splitList(values).map((value) => parseScalar(value, element));
}

export function headerArg(req: Request, name: string, shape: Shape, options: ArgOptions = {}): any {
   const values = headerValues(req, name);
   return values.length === 0 ? absent(name, options) : parseScalar(values[0], shape);
}

export function headerListArg(req: Request, name: string, element: Shape, options: ArgOptions = {}): any {
   const values = headerValues(req, name);
   return values.length === 0 ? absent(name, options) : splitList(values).map((value) => parseScalar(value, element));
}

export function hasBody(req: Request): boolean {
   return req.headers['transfer-encoding'] !== undefined || Number(req.headers['content-length'] ?? 0) > 0;
}

export function bodyArg(req: Request, shape: Shape, shapes: Shapes, options: ArgOptions = {}): any {
   if (!hasBody(req)) return absent('request body', options);
   if (!req.is('json')) throw new RestError(415, 'Unsupported media type');
   validate(req.body, shape, shapes);
   return req.body;
}

export type Params = Map<string, string[]>;

export function queryParams(req: Request): Params {
   const params: Params = new Map();
   const query = req.originalUrl.split('?')[1] ?? '';
   for (const [name, value] of new URLSearchParams(query)) params.set(name, [...(params.get(name) ?? []), value]);
   return params;
}

function childKeys(keys: string[], name: string): string[] {
   return keys.flatMap((key) => (key === '' ? [name] : [`${key}.${name}`, `${key}[${name}]`]));
}

function valuesOf(params: Params, keys: string[]): string[] {
   return keys.flatMap((key) => params.get(key) ?? []);
}

function readNested(params: Params, keys: string[], shape: Shape, shapes: Shapes): unknown {
   switch (shape.k) {
      case 'ref':
         return readNested(params, keys, shapes[shape.name], shapes);
      case 'object': {
         const result: Record<string, unknown> = {};
         for (const [name, field] of Object.entries(shape.fields)) {
            const child = readNested(params, childKeys(keys, name), field.shape, shapes);
            if (child !== null) result[name] = child;
         }
         return Object.keys(result).length === 0 ? null : result;
      }
      case 'list': {
         const element = shape.of.k === 'ref' ? shapes[shape.of.name] : shape.of;
         if (element.k !== 'object' && element.k !== 'list') {
            const values = splitList(valuesOf(params, keys));
            return values.length === 0 ? null : values.map((value) => parseScalar(value, element));
         }
         const items: unknown[] = [];
         for (let index = 0; ; index++) {
            const item = readNested(params, childKeys(keys, String(index)), shape.of, shapes);
            if (item === null) break;
            items.push(item);
         }
         return items.length === 0 ? null : items;
      }
      default: {
         const values = valuesOf(params, keys);
         return values.length === 0 ? null : parseScalar(values[0], shape);
      }
   }
}

export function nestedArg(params: Params, name: string, shape: Shape, shapes: Shapes, options: ArgOptions = {}): any {
   const value = readNested(params, [name], shape, shapes);
   if (value === null) return absent(name, options);
   validate(value, shape, shapes);
   return value;
}

export function jsonArg(params: Params, name: string, shape: Shape, shapes: Shapes, options: ArgOptions = {}): any {
   const text = params.get(name)?.[0];
   if (text === undefined) return absent(name, options);
   let value: unknown;
   try {
      value = JSON.parse(text);
   } catch {
      return bad(`Invalid JSON in ${name}`);
   }
   validate(value, shape, shapes);
   return value;
}

export interface FormFields {
   fields: Map<string, string[]>;
}

export function readForm(req: Request): FormFields {
   const form: FormFields = { fields: new Map() };
   if (!hasBody(req)) return form;
   if (!req.is('application/x-www-form-urlencoded')) throw new RestError(415, 'Expected application/x-www-form-urlencoded');
   const text = typeof req.body === 'string' ? req.body : '';
   for (const [name, value] of new URLSearchParams(text)) form.fields.set(name, [...(form.fields.get(name) ?? []), value]);
   return form;
}

export function formArg(form: FormFields, name: string, shape: Shape, options: ArgOptions = {}): any {
   const values = form.fields.get(name);
   return values === undefined ? absent(name, options) : parseScalar(values[0], shape);
}

export function formListArg(form: FormFields, name: string, element: Shape, options: ArgOptions = {}): any {
   const values = form.fields.get(name);
   return values === undefined ? absent(name, options) : splitList(values).map((value) => parseScalar(value, element));
}

export function checked(value: unknown, shape: Shape, shapes: Shapes): any {
   validate(value, shape, shapes);
   return value;
}

export function sendJson(res: Response, value: unknown): void {
   if (value === null || value === undefined) {
      res.status(200).end();
      return;
   }
   res.status(200).json(value);
}

export function wrap(value: unknown, path: string[]): unknown {
   return path.reduceRight((inner, key) => ({ [key]: inner }), value ?? null);
}

export function sendText(res: Response, value: string): void {
   res.status(200).type('text/plain').send(value);
}

export function sendNoContent(res: Response): void {
   res.status(204).end();
}

function sendError(res: Response, status: number): void {
   res.status(status).json({ status, error: reasons[status] ?? 'Error' });
}

export function handle(action: (req: Request, res: Response) => Promise<void>): RequestHandler {
   return (req, res) => {
      action(req, res).catch((error) => {
         if (res.headersSent) return;
         if (error instanceof RestError) {
            sendError(res, error.status);
            return;
         }
         console.error(error);
         sendError(res, 500);
      });
   };
}

export function methodNotAllowed(methods: string[]): RequestHandler {
   return (_req, res) => {
      res.set('Allow', methods.join(', '));
      sendError(res, 405);
   };
}

export function restErrorHandler(error: any, _req: Request, res: Response, next: NextFunction): void {
   if (res.headersSent) {
      next(error);
      return;
   }
   sendError(res, error?.status >= 400 && error?.status < 500 ? error.status : 500);
}

export function notFound(_req: Request, res: Response, _next?: NextFunction): void {
   sendError(res, 404);
}
''';

const expressRestUploadsFileName = 'uploads.ts';

const expressRestUploadsRaw = r'''export function rawUploadArg(req: Request): FileUpload {
   return {
      filename: '',
      mimetype: req.headers['content-type'] ?? 'application/octet-stream',
      encoding: '7bit',
      createReadStream: () => req,
   };
}
''';

const expressRestUploadsMultipart = r'''
export interface MultipartForm extends FormFields {
   files: Map<string, FileUpload[]>;
}

const defaultMaxFileSize = 100 * 1024 * 1024;

function push<T>(map: Map<string, T[]>, key: string, value: T): void {
   map.set(key, [...(map.get(key) ?? []), value]);
}

export async function readMultipart(req: Request, res: Response, maxFileSize = defaultMaxFileSize): Promise<MultipartForm> {
   const form: MultipartForm = { fields: new Map(), files: new Map() };
   if (!req.is('multipart/form-data')) {
      if (!hasBody(req)) return form;
      throw new RestError(415, 'Expected multipart/form-data');
   }
   const directory = await mkdtemp(join(tmpdir(), 'graphlink-'));
   res.on('close', () => {
      rm(directory, { recursive: true, force: true }).catch(() => undefined);
   });
   await new Promise<void>((resolve, reject) => {
      let parser: busboy.Busboy;
      try {
         parser = busboy({ headers: req.headers, defParamCharset: 'utf8', limits: { fileSize: maxFileSize } });
      } catch {
         reject(new RestError(400, 'Malformed multipart body'));
         return;
      }
      const writes: Promise<unknown>[] = [];
      const received: { index: number; name: string; file: FileUpload }[] = [];
      parser.on('field', (name, value) => push(form.fields, name, value));
      parser.on('file', (name, stream, info) => {
         const index = writes.length;
         const path = join(directory, String(index));
         let truncated = false;
         stream.on('limit', () => {
            truncated = true;
         });
         writes.push(
            pipeline(stream, createWriteStream(path)).then(
               () => {
                  if (truncated) return new RestError(413, 'File too large');
                  received.push({
                     index,
                     name,
                     file: {
                        filename: info.filename ?? '',
                        mimetype: info.mimeType,
                        encoding: info.encoding,
                        createReadStream: () => createReadStream(path),
                     },
                  });
                  return undefined;
               },
               () => new RestError(400, 'Malformed multipart body'),
            ),
         );
      });
      parser.on('error', () => reject(new RestError(400, 'Malformed multipart body')));
      parser.on('close', () => {
         Promise.all(writes).then((results) => {
            const failure = results.find((result) => result instanceof RestError);
            if (failure) return reject(failure);
            received.sort((a, b) => a.index - b.index).forEach((entry) => push(form.files, entry.name, entry.file));
            return resolve();
         });
      });
      req.pipe(parser);
   });
   return form;
}

function missing(name: string, options: ArgOptions): null {
   if (options.optional) return null;
   throw new RestError(400, `Missing ${name}`);
}

export function fileArg(form: MultipartForm, name: string, options: ArgOptions = {}): any {
   const files = form.files.get(name);
   return files === undefined ? missing(name, options) : files[0];
}

export function fileListArg(form: MultipartForm, name: string, options: ArgOptions = {}): any {
   return form.files.get(name) ?? missing(name, options);
}
''';

const expressRestDownloadFileName = 'download.ts';

const expressRestDownload = r'''/** What a service returns for a `@glDownload` scalar: the bytes (a stream is piped as is) and how to present them. */
export interface GraphLinkDownload {
   data: Readable | Uint8Array | string;
   filename?: string;
   contentType?: string;
   length?: number;
}

function contentDisposition(filename: string): string {
   const clean = filename.replace(/[\x00-\x1f\x7f]/g, '_');
   const ascii = clean.replace(/[^\x20-\x7e]/g, '?').replace(/["\\]/g, '\\$&');
   if (clean === ascii.replace(/\\(["\\])/g, '$1')) return `attachment; filename="${ascii}"`;
   const encoded = encodeURIComponent(clean).replace(/['()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
   return `attachment; filename="${ascii}"; filename*=UTF-8''${encoded}`;
}

export async function sendDownload(res: Response, download: GraphLinkDownload | null | undefined): Promise<void> {
   if (download === null || download === undefined) {
      res.status(204).end();
      return;
   }
   if (download.filename !== undefined) {
      res.attachment(download.filename);
      res.setHeader('Content-Disposition', contentDisposition(download.filename));
   }
   if (download.contentType !== undefined) res.type(download.contentType);
   else if (download.filename === undefined) res.type('application/octet-stream');
   const { data } = download;
   if (data instanceof Readable) {
      if (download.length !== undefined) res.setHeader('Content-Length', download.length);
      res.status(200);
      await pipeline(data, res);
      return;
   }
   const bytes = typeof data === 'string' ? Buffer.from(data) : data;
   res.status(200).setHeader('Content-Length', bytes.byteLength);
   res.end(bytes);
}
''';
