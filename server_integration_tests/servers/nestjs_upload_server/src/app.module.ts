import { Module } from '@nestjs/common';
import { GraphLinkModule } from './generated/index.js';
import { PingService } from './generated/services/ping-service.js';
import { UploadOneFileService } from './generated/services/upload-one-file-service.js';
import { UploadFileListService } from './generated/services/upload-file-list-service.js';
import { PingServiceImpl } from './impl/ping-service.js';
import { UploadOneFileServiceImpl } from './impl/upload-one-file-service.js';
import { UploadFileListServiceImpl } from './impl/upload-file-list-service.js';

@Module({
  providers: [
    { provide: PingService, useClass: PingServiceImpl },
    { provide: UploadOneFileService, useClass: UploadOneFileServiceImpl },
    { provide: UploadFileListService, useClass: UploadFileListServiceImpl },
  ],
  exports: [PingService, UploadOneFileService, UploadFileListService],
})
export class ServicesModule {}

@Module({ imports: [GraphLinkModule.forRoot({ imports: [ServicesModule] })] })
export class AppModule {}
