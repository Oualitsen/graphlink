package dev.graphlink.demo.services;

import dev.graphlink.demo.generated.services.UploadService;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.stream.Collectors;

@Service
public class UploadFileServiceImpl implements UploadService {

    @Override
    public Integer uploadFile(MultipartFile file) {
        if (file == null) {
            return 0;
        }
        return (int) file.getSize();
    }

    @Override
    public Integer uploadFileList(List<MultipartFile> file) {
        return file.stream().map(MultipartFile::getSize).reduce((a, b) -> a + b).get().intValue();
    }
}
