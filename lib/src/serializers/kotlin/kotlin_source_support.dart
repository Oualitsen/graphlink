const kotlinSourceSupportFileName = 'GraphLinkSource.kt';

const kotlinSourceSupportSource = '''
/** Keeps the object a service returned next to its map, so a schema mapping gets that same instance. */
object GraphLinkSource {
   const val KEY = "__glSource__"

   fun attach(json: Map<String, Any?>, source: Any): Map<String, Any?> {
      val carrier = LinkedHashMap(json)
      carrier[KEY] = source
      return carrier
   }

   fun <T : Any> of(json: Map<String, Any?>, type: Class<T>, fromJson: (Map<String, Any?>) -> T): T {
      val source = json[KEY]
      return if (type.isInstance(source)) type.cast(source) else fromJson(json)
   }
}
''';
