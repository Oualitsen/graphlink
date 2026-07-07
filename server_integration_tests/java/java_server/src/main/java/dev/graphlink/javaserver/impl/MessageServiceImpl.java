package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.services.MessageReadSchemaMappingsService;
import dev.graphlink.javaserver.generated.services.MessageService;
import dev.graphlink.javaserver.generated.types.Message;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class MessageServiceImpl implements MessageService, MessageReadSchemaMappingsService {

    @Override
    public List<Message> getMessageReadList() {
        return List.of(
            Message.builder().id("m1").content("hello").build(),
            Message.builder().id("m2").content("world").build());
    }

    @Override
    public Map<Message, Boolean> messageReadRead(List<Message> value) {
        Map<Message, Boolean> result = new LinkedHashMap<>();
        for (Message m : value) {
            result.put(m, m.getId().endsWith("1"));
        }
        return result;
    }
}
