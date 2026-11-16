import { createHash } from 'node:crypto';
import { FileUpload } from '../generated/file-upload.js';
import { RestUploadInfoService } from '../generated/services/rest-upload-info-service.js';
import { RestUploadOptionalService } from '../generated/services/rest-upload-optional-service.js';
import { RestUploadInfo } from '../generated/types/rest-upload-info.js';
import { GraphLinkContext } from '../generated/context.js';
import { RestColor } from '../generated/enums/rest-color.js';
import { RestFilter } from '../generated/inputs/rest-filter.js';
import { RestItemInput } from '../generated/inputs/rest-item-input.js';
import { RestMeta } from '../generated/inputs/rest-meta.js';
import { RestValidatedGuard } from '../generated/guards/rest-validated-guard.js';
import { RestColorsService } from '../generated/services/rest-colors-service.js';
import { RestCountService } from '../generated/services/rest-count-service.js';
import { RestDeleteService } from '../generated/services/rest-delete-service.js';
import { RestFormEchoService } from '../generated/services/rest-form-echo-service.js';
import { RestFormOptionalService } from '../generated/services/rest-form-optional-service.js';
import { RestFormEcho } from '../generated/types/rest-form-echo.js';
import { RestInterceptedVoidService } from '../generated/services/rest-intercepted-void-service.js';
import { RestMarkedService } from '../generated/services/rest-marked-service.js';
import { RestMarked } from '../generated/types/rest-marked.js';
import { Readable } from 'node:stream';
import { GraphLinkDownload } from '../generated/rest/download.js';
import { RestDownloadLargeService } from '../generated/services/rest-download-large-service.js';
import { RestDownloadOptionalService } from '../generated/services/rest-download-optional-service.js';
import { RestDownloadService } from '../generated/services/rest-download-service.js';
import { RestWrapColorService } from '../generated/services/rest-wrap-color-service.js';
import { RestWrapService } from '../generated/services/rest-wrap-service.js';
import { RestWrapTextService } from '../generated/services/rest-wrap-text-service.js';
import { RestWrap } from '../generated/types/rest-wrap.js';
import { RestNestedService } from '../generated/services/rest-nested-service.js';
import { RestNested } from '../generated/types/rest-nested.js';
import { RestLine } from '../generated/inputs/rest-line.js';
import { RestPerson } from '../generated/inputs/rest-person.js';
import { RestFlagService } from '../generated/services/rest-flag-service.js';
import { RestGreetingService } from '../generated/services/rest-greeting-service.js';
import { RestHeadersService } from '../generated/services/rest-headers-service.js';
import { RestKeywordsService } from '../generated/services/rest-keywords-service.js';
import { RestItemService } from '../generated/services/rest-item-service.js';
import { RestOptionalBodyService } from '../generated/services/rest-optional-body-service.js';
import { RestPlainService } from '../generated/services/rest-plain-service.js';
import { RestScalarsService } from '../generated/services/rest-scalars-service.js';
import { RestSearchService } from '../generated/services/rest-search-service.js';
import { RestTagsService } from '../generated/services/rest-tags-service.js';
import { RestValidatedService } from '../generated/services/rest-validated-service.js';
import { RestHeaders } from '../generated/types/rest-headers.js';
import { RestItem } from '../generated/types/rest-item.js';
import { RestKeywords } from '../generated/types/rest-keywords.js';
import { RestScalars } from '../generated/types/rest-scalars.js';
import { RestSearch } from '../generated/types/rest-search.js';

function item(id: string, name: string, qty: number, color: RestColor | null, tags: string[] | null): RestItem {
  return { id, name, qty, color, tags: tags ?? [] };
}

function fromInput(id: string, input: RestItemInput): RestItem {
  return item(id, input.name, input.qty, input.color ?? null, input.tags ?? null);
}

export class RestItemServiceImpl implements RestItemService {
  async restItem(id: string): Promise<RestItem | null> {
    return id === 'missing' ? null : item(id, `item-${id}`, 1, null, null);
  }

  async restItemByColor(color: RestColor): Promise<RestItem> {
    const lower = RestColor.toJson(color).toLowerCase();
    return item(lower, `color-${RestColor.toJson(color)}`, 1, color, [lower]);
  }

  async restItemGraphql(id: string): Promise<RestItem | null> {
    return this.restItem(id);
  }

  async restCreate(input: RestItemInput): Promise<RestItem> {
    return fromInput(`new-${input.name}`, input);
  }

  async restReplace(id: string, input: RestItemInput): Promise<RestItem> {
    return fromInput(id, input);
  }

  async restPatch(id: string, name: string | null): Promise<RestItem> {
    return item(id, name ?? `item-${id}`, 1, null, null);
  }

  async restBulk(items: RestItemInput[]): Promise<RestItem[]> {
    return items.map((input, i) => fromInput(`bulk-${i}`, input));
  }
}

export class RestScalarsServiceImpl implements RestScalarsService {
  async restScalars(n: number, ratio: number, flag: boolean, text: string): Promise<RestScalars> {
    return { n, ratio, flag, text };
  }

  async restFail(code: number): Promise<RestScalars> {
    throw new Error(`boom ${code}`);
  }
}

export class RestSearchServiceImpl implements RestSearchService {
  async restSearch(filter: RestFilter | null, limit: number | null, offset: number | null, order: RestColor | null): Promise<RestSearch> {
    return {
      tag: filter?.tag ?? null,
      minQty: filter?.minQty ?? null,
      maxPrice: filter?.maxPrice ?? null,
      colors: filter?.colors ?? null,
      inStock: filter?.inStock ?? null,
      limit: limit ?? 10,
      offset,
      order,
    };
  }
}

export class RestTagsServiceImpl implements RestTagsService {
  async restTags(tags: string[], ids: number[] | null): Promise<string[]> {
    return [...tags, ...(ids ?? []).map((id) => `#${id}`)];
  }
}

export class RestGreetingServiceImpl implements RestGreetingService {
  async restGreeting(name: string): Promise<string> {
    return `hello ${name}`;
  }
}

export class RestPlainServiceImpl implements RestPlainService {
  async restPlain(name: string): Promise<string> {
    return `plain ${name}`;
  }
}

export class RestCountServiceImpl implements RestCountService {
  async restCount(): Promise<number> {
    return 42;
  }
}

export class RestFlagServiceImpl implements RestFlagService {
  async restFlag(on: boolean): Promise<boolean> {
    return !on;
  }
}

export class RestColorsServiceImpl implements RestColorsService {
  async restColors(): Promise<RestColor[]> {
    return [RestColor.Red, RestColor.Green, RestColor.Blue];
  }
}

export class RestHeadersServiceImpl implements RestHeadersService {
  async restHeaders(token: string, trace: string | null, meta: RestMeta | null): Promise<RestHeaders> {
    return { token, trace, traceId: meta?.traceId ?? null, version: meta?.version ?? null };
  }
}

export class RestDeleteServiceImpl implements RestDeleteService {
  async restDelete(_id: string): Promise<void> {}
}

export class RestOptionalBodyServiceImpl implements RestOptionalBodyService {
  async restOptionalBody(input: RestItemInput | null): Promise<number> {
    return input?.qty ?? -1;
  }
}

export class RestValidatedServiceImpl implements RestValidatedService {
  async restValidated(_name: string): Promise<boolean> {
    return true;
  }
}

export class RestValidatedGuardImpl implements RestValidatedGuard {
  async validateRestValidated(name: string, _context: GraphLinkContext): Promise<void> {
    if (name === 'invalid') throw new Error('invalid name');
  }
}

export class RestKeywordsServiceImpl implements RestKeywordsService {
  async restKeywords(switch_: string, class_: string, return_: string | null, if_: number): Promise<RestKeywords> {
    return { class: class_, return: return_, if: if_, switch: switch_ };
  }
}

async function uploadInfo(file: FileUpload, label: string | null, kind: RestColor | null, times: number | null): Promise<RestUploadInfo> {
  const hash = createHash('sha256');
  let size = 0;
  for await (const chunk of file.createReadStream()) {
    const bytes = chunk as Buffer;
    hash.update(bytes);
    size += bytes.length;
  }
  return { filename: file.filename || null, contentType: file.mimetype, size, sha256: hash.digest('hex'), label, kind, times };
}

export class RestUploadInfoServiceImpl implements RestUploadInfoService {
  async restUpload(file: FileUpload, label: string | null, kind: RestColor | null, times: number | null): Promise<RestUploadInfo> {
    return uploadInfo(file, label, kind, times);
  }

  async restUploadMany(files: FileUpload[], label: string | null): Promise<RestUploadInfo[]> {
    return Promise.all(files.map((file) => uploadInfo(file, label, null, null)));
  }

  async restUploadRaw(_id: string, file: FileUpload, name: string | null): Promise<RestUploadInfo> {
    return uploadInfo(file, name, null, null);
  }
}

export class RestUploadOptionalServiceImpl implements RestUploadOptionalService {
  async restUploadOptional(file: FileUpload | null): Promise<number> {
    if (file === null) return -1;
    return (await uploadInfo(file, null, null, null)).size;
  }
}

export class RestFormEchoServiceImpl implements RestFormEchoService {
  async restForm(
    name: string,
    qty: number,
    color: RestColor | null,
    flag: boolean | null,
    tags: string[] | null,
    note: string | null,
  ): Promise<RestFormEcho> {
    return { id: null, name, qty, color, flag: flag ?? false, tags: tags ?? [], note };
  }

  async restFormUpdate(id: string, name: string, qty: number | null): Promise<RestFormEcho> {
    return { id, name, qty: qty ?? 1, color: null, flag: false, tags: [], note: null };
  }
}

export class RestFormOptionalServiceImpl implements RestFormOptionalService {
  async restFormOptional(note: string | null): Promise<number> {
    return note === null ? -1 : note.length;
  }
}

function marked(name: string, context: GraphLinkContext | null): RestMarked {
  return { name, marker: context?.marker ?? null, hasContext: context !== null };
}

export class RestMarkedServiceImpl implements RestMarkedService {
  async restIntercepted(name: string, context: GraphLinkContext): Promise<RestMarked> {
    return marked(name, context);
  }

  async restInjected(name: string, context: GraphLinkContext): Promise<RestMarked> {
    return marked(name, context);
  }

  async restUnguarded(name: string): Promise<RestMarked> {
    return marked(name, null);
  }

  async restBlockGuarded(name: string, context: GraphLinkContext): Promise<RestMarked> {
    return marked(name, context);
  }

  async restInterceptedBody(input: RestItemInput, context: GraphLinkContext): Promise<RestMarked> {
    return marked(input.name, context);
  }
}

export class RestInterceptedVoidServiceImpl implements RestInterceptedVoidService {
  async restInterceptedVoid(): Promise<void> {}
}

function pattern(size: number): Buffer {
  return Buffer.from(Array.from({ length: size }, (_, i) => i % 251));
}

function download(name: string, kind: string | null): GraphLinkDownload {
  switch (kind) {
    case 'bin':
      return { data: pattern(1000), filename: 'data.bin' };
    case 'nofile':
      return { data: 'x' };
    case 'type':
      return { data: '{"a":1}', contentType: 'application/json' };
    default:
      return { data: `hello ${name}`, filename: `${name}.txt`, contentType: 'text/plain' };
  }
}

export class RestDownloadServiceImpl implements RestDownloadService {
  async restDownload(name: string, kind: string | null): Promise<GraphLinkDownload> {
    return download(name, kind);
  }
}

export class RestDownloadOptionalServiceImpl implements RestDownloadOptionalService {
  async restDownloadOptional(name: string | null): Promise<GraphLinkDownload | null> {
    return name === null ? null : download(name, null);
  }
}

export class RestDownloadLargeServiceImpl implements RestDownloadLargeService {
  async restDownloadLarge(size: number): Promise<GraphLinkDownload> {
    let position = 0;
    const data = new Readable({
      read() {
        const count = Math.min(64 * 1024, size - position);
        if (count <= 0) {
          this.push(null);
          return;
        }
        this.push(Buffer.from(Array.from({ length: count }, (_, i) => (position + i) % 251)));
        position += count;
      },
    });
    return { data, filename: 'large.bin' };
  }
}

export class RestWrapServiceImpl implements RestWrapService {
  async restWrapDeep(v: string): Promise<RestWrap> {
    return { value: v };
  }

  async restWrapList(n: number): Promise<RestWrap[]> {
    return Array.from({ length: n }, (_, i) => ({ value: `item-${i}` }));
  }

  async restWrapNullable(on: boolean): Promise<RestWrap | null> {
    return on ? { value: 'on' } : null;
  }
}

export class RestWrapColorServiceImpl implements RestWrapColorService {
  async restWrapColor(): Promise<RestColor> {
    return RestColor.Blue;
  }
}

export class RestWrapTextServiceImpl implements RestWrapTextService {
  async restWrapText(v: string): Promise<string> {
    return `text:${v}`;
  }
}

function personSummary(person: RestPerson | null): string {
  if (person === null) return 'none';
  return [
    person.name,
    person.age ?? '-',
    person.address?.city ?? '-',
    person.address?.zip ?? '-',
    person.tags ? person.tags.join(',') : '-',
    person.kind ?? '-',
  ].join('|');
}

function linesSummary(lines: RestLine[] | null): string {
  return lines === null ? '-' : lines.map((line) => `${line.sku}:${line.qty}`).join(';');
}

export class RestNestedServiceImpl implements RestNestedService {
  async restNestedSpread(person: RestPerson): Promise<RestNested> {
    return { summary: personSummary(person) };
  }

  async restNestedSpreadOptional(person: RestPerson | null): Promise<RestNested> {
    return { summary: personSummary(person) };
  }

  async restNestedFlat(person: RestPerson): Promise<RestNested> {
    return { summary: personSummary(person) };
  }

  async restNestedLines(lines: RestLine[]): Promise<RestNested> {
    return { summary: linesSummary(lines) };
  }

  async restNestedJson(person: RestPerson | null): Promise<RestNested> {
    return { summary: personSummary(person) };
  }

  async restNestedForm(person: RestPerson, lines: RestLine[] | null, note: string | null): Promise<RestNested> {
    return { summary: `${personSummary(person)}/${linesSummary(lines)}/${note ?? '-'}` };
  }

  async restNestedFormJson(person: RestPerson): Promise<RestNested> {
    return { summary: personSummary(person) };
  }
}
