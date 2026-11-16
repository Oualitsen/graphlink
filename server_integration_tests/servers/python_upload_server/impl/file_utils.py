from generated.file_upload import FileUpload


async def read_file(file: FileUpload) -> bytes:
    chunks = []
    async for chunk in file.create_read_stream():
        chunks.append(chunk)
    return b"".join(chunks)
