package dev.graphlink.javaserver.impl;

import dev.graphlink.javaserver.generated.enums.Keyword;
import dev.graphlink.javaserver.generated.inputs.ReservedInput;
import dev.graphlink.javaserver.generated.services.ReservedFieldsService;
import dev.graphlink.javaserver.generated.types.Class;
import dev.graphlink.javaserver.generated.types.ReservedFields;
import dev.graphlink.javaserver.generated.types.Secret_;
import org.springframework.stereotype.Service;

@Service
public class ReservedFieldsServiceImpl implements ReservedFieldsService {

    private ReservedFields.Builder base() {
        return ReservedFields.builder()
            .id("r1")
            .class_("cls")
            .return_(42)
            .new_(true)
            .default_("def")
            .is("yes")
            .in("inside")
            .with("w")
            .int_(7)
            .synchronized_(false)
            .native_("n")
            .kind(Keyword.CLASS)
            .nested(Class.builder().id("c1").value("v").build())
            .secret(Secret_.builder().id("s1").token("tok").build());
    }

    @Override
    public ReservedFields reserved() {
        return base().build();
    }

    @Override
    public ReservedFields switch_(String class_, Integer return_) {
        return base().class_(class_).return_(return_ != null ? return_ : 0).build();
    }

    @Override
    public ReservedFields echoReserved(ReservedInput input) {
        return base()
            .class_(input.getClass_())
            .return_(input.getReturn_() != null ? input.getReturn_() : -1)
            .default_(input.getDefault_() != null ? input.getDefault_() : "none")
            .build();
    }
}
