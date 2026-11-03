package dev.graphlink.test;

import dev.graphlink.test.generated.client.GLUpload;
import dev.graphlink.test.generated.client.GraphLinkMultipartAdapter;
import dev.graphlink.test.generated.client.UploadProgressCallback;
import io.smallrye.mutiny.Uni;

import java.util.Map;

public class RealMultipartAdapter extends RealMultipartCore implements GraphLinkMultipartAdapter {

    public RealMultipartAdapter(String url) { super(url); }

    @Override
    public Uni<String> executeMultipart(String operations, String mapJson,
                                         Map<String, GLUpload> files,
                                         UploadProgressCallback onProgress) {
        return Rx.deferred(() -> send(operations, mapJson, files));
    }
}
