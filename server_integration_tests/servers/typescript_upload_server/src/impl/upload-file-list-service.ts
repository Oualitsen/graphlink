import { UploadFileListService } from '../generated/services/upload-file-list-service.js';
import { FileUpload } from '../generated/file-upload.js';
import { UploadRejected } from '../generated/errors/upload-rejected.js';
import { readFile } from './file-utils.js';

export class UploadFileListServiceImpl implements UploadFileListService {
  async uploadFileList(userId: string, files: FileUpload[]): Promise<boolean> {
    if (files.length === 0) return false;
    if (userId === 'rejected') {
      for (const file of files) await readFile(file);
      throw new UploadRejected({ userId, reason: 'quota exceeded', message: 'Upload rejected' });
    }
    for (const file of files) {
      const bytes = await readFile(file);
      if (bytes.length === 0) return false;
    }
    return true;
  }
}
