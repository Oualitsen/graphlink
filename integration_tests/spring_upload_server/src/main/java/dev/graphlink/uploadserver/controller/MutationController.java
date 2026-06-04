package dev.graphlink.uploadserver.controller;

import org.springframework.graphql.data.method.annotation.Argument;
import org.springframework.graphql.data.method.annotation.MutationMapping;
import org.springframework.stereotype.Controller;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

@Controller
public class MutationController {

    @MutationMapping
    public boolean uploadOneFile(@Argument String userId, @Argument MultipartFile file) {
        return file != null && !file.isEmpty();
    }

    @MutationMapping
    public boolean uploadFileList(@Argument String userId, @Argument List<MultipartFile> files) {
        return files != null && !files.isEmpty() && files.stream().allMatch(f -> f != null && !f.isEmpty());
    }
}
