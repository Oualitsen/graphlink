/// Emitted once per Spring server (no per-schema templating). The mappified
/// controllers return `Map<String, Object>` for every projectable value, so
/// graphql-java's default class-name based type resolution can't tell which
/// concrete object type an interface/union value is. Each map carries its
/// concrete type under `__typename` (from `toJson()`); this wiring factory
/// registers a single resolver for every interface and union that reads it.
///
/// Package-agnostic: `writeToFile` prepends `package <base>.<subdir>;`.
const springMapTypeResolverConfigFileName = 'GraphLinkMapTypeResolverConfig.java';

const springMapTypeResolverConfigSource = '''
import java.util.Map;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.graphql.execution.RuntimeWiringConfigurer;

import graphql.TypeResolutionEnvironment;
import graphql.schema.GraphQLObjectType;
import graphql.schema.TypeResolver;
import graphql.schema.idl.InterfaceWiringEnvironment;
import graphql.schema.idl.UnionWiringEnvironment;
import graphql.schema.idl.WiringFactory;

@Configuration
public class GraphLinkMapTypeResolverConfig {

   private static final TypeResolver MAP_TYPE_RESOLVER = new TypeResolver() {
      @Override
      public GraphQLObjectType getType(TypeResolutionEnvironment env) {
         Object source = env.getObject();
         if (source instanceof Map<?, ?> map) {
            Object typename = map.get("__typename");
            if (typename != null) {
               return env.getSchema().getObjectType(typename.toString());
            }
         }
         return null;
      }
   };

   @Bean
   public RuntimeWiringConfigurer mapTypeResolvers() {
      return builder -> builder.wiringFactory(new WiringFactory() {
         @Override
         public boolean providesTypeResolver(InterfaceWiringEnvironment env) {
            return true;
         }

         @Override
         public TypeResolver getTypeResolver(InterfaceWiringEnvironment env) {
            return MAP_TYPE_RESOLVER;
         }

         @Override
         public boolean providesTypeResolver(UnionWiringEnvironment env) {
            return true;
         }

         @Override
         public TypeResolver getTypeResolver(UnionWiringEnvironment env) {
            return MAP_TYPE_RESOLVER;
         }
      });
   }
}
''';
