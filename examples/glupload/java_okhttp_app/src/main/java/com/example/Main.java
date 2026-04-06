package com.example;

import com.example.generated.client.GLUpload;
import com.example.generated.client.GraphLinkClient;
import com.example.generated.types.UploadedFile;
import com.example.generated.types.UploadFileResponse;
import com.example.generated.types.UploadFilesResponse;

import java.io.File;
import java.io.IOException;
import java.util.List;

public class Main {

    private static final String ENDPOINT = "http://localhost:8080/graphql";

    public static void main(String[] args) throws IOException {
        GraphLinkClient client = new GraphLinkClient(ENDPOINT);

        uploadSingleFile(client);
        uploadMultipleFiles(client);
    }

    // Single file — upload config.json
    static void uploadSingleFile(GraphLinkClient client) throws IOException {
        GLUpload upload = GLUpload.fromFile(new File("config.json"), "application/json");

        UploadFileResponse response = client.mutations.uploadFile(
                upload,
                "config.json",
                (sent, total) -> System.out.printf("[single] %.0f%%%n", total > 0 ? sent * 100.0 / total : 0)
        );

        UploadedFile uploaded = response.getUploadFile();
        System.out.println("Uploaded: " + uploaded.getUrl() + " (" + uploaded.getSize() + " bytes)");
    }

    // Multiple files — upload config.json + pom.xml
    static void uploadMultipleFiles(GraphLinkClient client) throws IOException {
        List<GLUpload> uploads = List.of(
                GLUpload.fromFile(new File("config.json"), "application/json"),
                GLUpload.fromFile(new File("pom.xml"), "application/xml")
        );

        UploadFilesResponse response = client.mutations.uploadFiles(
                uploads,
                "project-files",
                (sent, total) -> System.out.printf("[multi] %.0f%%%n", total > 0 ? sent * 100.0 / total : 0)
        );

        List<UploadedFile> files = response.getUploadFiles();
        System.out.println("Uploaded " + files.size() + " file(s):");
        for (UploadedFile f : files) {
            System.out.println("  " + f.getFilename() + " → " + f.getUrl());
        }
    }
}
