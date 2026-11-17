def build_services(services_cls, mode="mix"):
    from impl.interceptor import InterceptorImpl

    services = {"interceptor": InterceptorImpl()}
    if mode != "rest":
        from impl.wiring_graphql import graphql_services

        services.update(graphql_services())
    if mode != "graphql":
        from impl.wiring_rest import rest_services

        services.update(rest_services())
    return services_cls(**services)
