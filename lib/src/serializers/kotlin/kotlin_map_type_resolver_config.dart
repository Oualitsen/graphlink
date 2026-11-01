/// Kotlin counterpart of the Java Spring map type resolver (see
/// `spring_map_type_resolver_config.dart`). The mappified controllers return
/// `Map<String, Any?>` for every projectable value, so graphql-java's default
/// class-name based type resolution can't tell which concrete object type an
/// interface/union value is. Each map carries its concrete type under
/// `__typename` (from `toJson()`); this wiring factory registers a single
/// resolver for every interface and union that reads it.
///
/// Package-agnostic: `writeToFile` prepends `package <base>.<subdir>`.
const kotlinMapTypeResolverConfigFileName = 'GraphLinkMapTypeResolverConfig.kt';

const kotlinMapTypeResolverConfigSource = '''
import graphql.schema.TypeResolver
import graphql.schema.idl.InterfaceWiringEnvironment
import graphql.schema.idl.UnionWiringEnvironment
import graphql.schema.idl.WiringFactory
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.graphql.execution.RuntimeWiringConfigurer

@Configuration
class GraphLinkMapTypeResolverConfig {

    private val mapTypeResolver = TypeResolver { env ->
        val source: Any? = env.getObject()
        val typename = (source as? Map<*, *>)?.get("__typename")
        if (typename != null) env.schema.getObjectType(typename.toString()) else null
    }

    @Bean
    fun mapTypeResolvers(): RuntimeWiringConfigurer = RuntimeWiringConfigurer { builder ->
        builder.wiringFactory(object : WiringFactory {
            override fun providesTypeResolver(env: InterfaceWiringEnvironment): Boolean = true

            override fun getTypeResolver(env: InterfaceWiringEnvironment): TypeResolver = mapTypeResolver

            override fun providesTypeResolver(env: UnionWiringEnvironment): Boolean = true

            override fun getTypeResolver(env: UnionWiringEnvironment): TypeResolver = mapTypeResolver
        })
    }
}
''';
