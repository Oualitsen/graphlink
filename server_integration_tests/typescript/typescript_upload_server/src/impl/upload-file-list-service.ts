import { UploadFileListService } from '../generated/services/upload-file-list-service.js';
import { FileUpload } from '../generated/file-upload.js';
import { readFile } from './file-utils.js';

export class UploadFileListServiceImpl implements UploadFileListService {
  async uploadFileList(userId: string, files: FileUpload[]): Promise<boolean> {
    if (files.length === 0) return false;
    for (const file of files) {
      const bytes = await readFile(file);
      if (bytes.length === 0) return false;
    }
    return true;
  }
}
