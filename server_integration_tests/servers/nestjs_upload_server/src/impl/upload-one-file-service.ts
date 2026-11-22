import { UploadOneFileService } from '../generated/services/upload-one-file-service.js';
import { FileUpload } from '../generated/file-upload.js';
import { UploadRejected } from '../generated/errors/upload-rejected.js';
import { readFile } from './file-utils.js';

export class UploadOneFileServiceImpl implements UploadOneFileService {
  async uploadOneFile(userId: string, file: FileUpload): Promise<boolean> {
    const bytes = await readFile(file);
    if (userId === 'rejected') throw new UploadRejected({ userId, reason: 'quota exceeded', message: 'Upload rejected' });
    return bytes.length > 0;
  }
}
