import { FileUpload } from '../generated/file-upload.js';

export async function readFile(file: FileUpload): Promise<Buffer> {
  const chunks: Buffer[] = [];
  for await (const chunk of file.createReadStream()) {
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks);
}
