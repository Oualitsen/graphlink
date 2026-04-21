import { UploadResultService } from '../generated/services/upload-result-service.js';
import { UploadResult } from '../generated/types/upload-result.js';
import { GraphLinkContext } from '../generated/context.js';
import { GraphQLResolveInfo } from 'graphql';
import type { FileUpload } from '../generated/file-upload.js';

export class MyUploadResultService implements UploadResultService {
  async uploadFile(file: FileUpload, context: GraphLinkContext, info: GraphQLResolveInfo): Promise<UploadResult> {
    const { filename, mimetype, createReadStream } = file;
    const stream = createReadStream();
    let size = 0;
    await new Promise<void>((resolve, reject) => {
      stream.on('data', (chunk: Buffer) => { size += chunk.length; });
      stream.on('end', resolve);
      stream.on('error', reject);
    });
    return { filename, mimetype, size };
  }
}
