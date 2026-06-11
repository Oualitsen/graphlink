import './impl/my-context.js';
import { createServer } from './generated/index.js';
import { PingServiceImpl } from './impl/ping-service.js';
import { UploadOneFileServiceImpl } from './impl/upload-one-file-service.js';
import { UploadFileListServiceImpl } from './impl/upload-file-list-service.js';

const PORT = 9996;

const httpServer = await createServer({
  pingService: new PingServiceImpl(),
  uploadOneFileService: new UploadOneFileServiceImpl(),
  uploadFileListService: new UploadFileListServiceImpl(),
});

httpServer.listen(PORT, () => {
  console.log(`Server ready at http://localhost:${PORT}/graphql`);
});
