import { UploadOneFileService } from '../generated/services/upload-one-file-service.js';
import { FileUpload } from '../generated/file-upload.js';
import { readFile } from './file-utils.js';

export class UploadOneFileServiceImpl implements UploadOneFileService {
  async uploadOneFile(userId: string, file: FileUpload): Promise<boolean> {
    const bytes = await readFile(file);
    return bytes.length > 0;
  }
}
