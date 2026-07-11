package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.enums.Priority;
import dev.graphlink.javaserver.generated.inputs.ConfigInput;
import dev.graphlink.javaserver.generated.inputs.RangeInput;
import dev.graphlink.javaserver.generated.services.AckPriorityService;
import dev.graphlink.javaserver.generated.services.ConfigService;
import dev.graphlink.javaserver.generated.services.EchoPriorityService;
import dev.graphlink.javaserver.generated.services.GreetService;
import dev.graphlink.javaserver.generated.services.RangeService;
import dev.graphlink.javaserver.generated.types.Config;
import dev.graphlink.javaserver.generated.types.Range;
import org.springframework.stereotype.Service;
import reactor.core.publisher.Mono;

/**
 * Default/initial-value resolvers: each simply reflects its effective input
 * back, so a client that omits a defaulted field/argument can assert the
 * schema default was applied end-to-end.
 */
@Service
public class DefaultsServiceImpl
        implements ConfigService, RangeService, GreetService, EchoPriorityService, AckPriorityService {

    @Override
    public Mono<Config> resolveConfig(ConfigInput input) {
        return Mono.just(Config.builder()
            .pageSize(input.getPageSize())
            .ratio(input.getRatio())
            .sort(input.getSort())
            .verbose(input.getVerbose())
            .priority(input.getPriority())
            .tags(input.getTags())
            .empties(input.getEmpties())
            .note(input.getNote())
            .build());
    }

    @Override
    public Mono<Range> resolveRange(RangeInput input) {
        return Mono.just(Range.builder().min(input.getMin()).max(input.getMax()).build());
    }

    @Override
    public Mono<String> greet(String name, Integer times) {
        return Mono.just(("Hi " + name + "!").repeat(times));
    }

    @Override
    public Mono<Priority> echoPriority(Priority level) {
        return Mono.just(level);
    }

    @Override
    public Mono<String> ackPriority(Priority level) {
        return Mono.just("OK");
    }
}
