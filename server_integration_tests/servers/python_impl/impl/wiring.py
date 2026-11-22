def build_services(services_cls, mode="mix"):
    from impl.interceptor import InterceptorImpl

    services = {"interceptor": InterceptorImpl()}
    if mode != "rest":
        from impl.wiring_graphql import graphql_services

        services.update(graphql_services())
    if mode != "graphql":
        from impl.wiring_rest import rest_services

        services.update(rest_services())
    if mode == "mix" and "err_item_service" in getattr(services_cls, "__dataclass_fields__", {}):
        from impl.wiring_errors import ErrItemServiceImpl

        services["err_item_service"] = ErrItemServiceImpl()
    return services_cls(**services)
