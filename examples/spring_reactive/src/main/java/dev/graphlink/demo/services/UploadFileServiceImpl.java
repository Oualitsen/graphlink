package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.services.UploadFileService;
import org.springframework.http.codec.multipart.FilePart;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

@Service
public class UploadFileServiceImpl implements UploadFileService {

    @Override
    public Mono<Integer> uploadFile(FilePart file) {
        // Dummy implementation: drain the file content and return a fixed size
        return file.content()
                .map(dataBuffer -> dataBuffer.readableByteCount())
                .reduce(0, Integer::sum);
    }
}
