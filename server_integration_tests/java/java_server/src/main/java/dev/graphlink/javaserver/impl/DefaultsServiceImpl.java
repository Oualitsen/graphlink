package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.inputs.ConfigInput;
import dev.graphlink.javaserver.generated.inputs.RangeInput;
import dev.graphlink.javaserver.generated.services.ConfigService;
import dev.graphlink.javaserver.generated.services.GreetService;
import dev.graphlink.javaserver.generated.services.RangeService;
import dev.graphlink.javaserver.generated.types.Config;
import dev.graphlink.javaserver.generated.types.Range;
import org.springframework.stereotype.Service;

/**
 * Default/initial-value resolvers: each simply reflects its effective input
 * back, so a client that omits a defaulted field/argument can assert the
 * schema default was applied end-to-end.
 */
@Service
public class DefaultsServiceImpl implements ConfigService, RangeService, GreetService {

    @Override
    public Config resolveConfig(ConfigInput input) {
        return Config.builder()
            .pageSize(input.getPageSize())
            .ratio(input.getRatio())
            .sort(input.getSort())
            .verbose(input.getVerbose())
            .priority(input.getPriority())
            .tags(input.getTags())
            .empties(input.getEmpties())
            .note(input.getNote())
            .build();
    }

    @Override
    public Range resolveRange(RangeInput input) {
        return Range.builder().min(input.getMin()).max(input.getMax()).build();
    }

    @Override
    public String greet(String name, Integer times) {
        return ("Hi " + name + "!").repeat(times);
    }
}
