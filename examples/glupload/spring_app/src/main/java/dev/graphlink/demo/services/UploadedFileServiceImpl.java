package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.services.UploadedFileService;
import dev.graphlink.demo.generated.types.UploadedFile;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

@Slf4j
@Service
public class UploadedFileServiceImpl implements UploadedFileService {

    private final Path root = Paths.get("uploads");
    private final Map<String, UploadedFile> fileMetadataMap = new ConcurrentHashMap<>();

    public UploadedFileServiceImpl() {
        try {
            Files.createDirectories(root);
        } catch (IOException e) {
            throw new RuntimeException("Could not initialize folder for upload!");
        }
    }

    @Override
    public List<UploadedFile> files() {
        return new ArrayList<>(fileMetadataMap.values());
    }

    @Override
    public UploadedFile file(String id) {
        return fileMetadataMap.get(id);
    }

    @Override
    public UploadedFile uploadFile(MultipartFile file, String filename) {
        log.info("Uploading file {}", file.getOriginalFilename());
        try {
            String id = UUID.randomUUID().toString();
            String actualFilename = filename != null && !filename.isEmpty() ? filename : file.getOriginalFilename();
            String fileExtension = getFileExtension(file.getOriginalFilename());
            if (actualFilename != null && !actualFilename.endsWith(fileExtension)) {
                actualFilename += fileExtension;
            }
            
            Path filePath = this.root.resolve(id + "_" + actualFilename);
            Files.copy(file.getInputStream(), filePath);

            UploadedFile uploadedFile = UploadedFile.builder()
                    .id(id)
                    .filename(actualFilename)
                    .mimeType(file.getContentType())
                    .size((int) file.getSize())
                    .url(filePath.toString())
                    .build();

            fileMetadataMap.put(id, uploadedFile);
            return uploadedFile;
        } catch (Exception e) {
            throw new RuntimeException("Could not store the file. Error: " + e.getMessage());
        }
    }

    @Override
    public List<UploadedFile> uploadFiles(List<MultipartFile> files, String label) {
        return files.stream()
                .map(file -> uploadFile(file, null))
                .collect(Collectors.toList());
    }

    @Override
    public UploadedFile uploadAvatar(MultipartFile file, String userId) {
        // For avatar, we could potentially overwrite or name it specifically
        return uploadFile(file, "avatar_" + userId);
    }

    private String getFileExtension(String filename) {
        if (filename == null) return "";
        int lastIndex = filename.lastIndexOf('.');
        return (lastIndex == -1) ? "" : filename.substring(lastIndex);
    }
}
