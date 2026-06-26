import 'package:graphlink/src/config.dart';

/// Strategy object that encapsulates every per-library divergence needed to
/// generate reactive Java client code for Reactor, RxJava3 and Mutiny.
///
/// The three libraries are the same monad shape with different names, so the
/// generated code path is identical except for: the wrapper type names
/// (`Mono`/`Flux` vs `Single`/`Observable` vs `Uni`/`Multi`), the factory
/// snippets used to lift a value/callable into the deferred-single type, and a
/// couple of combinators whose API shape differs (notably Mutiny).
///
/// [JavaAsyncStyle.blocking] maps to the degenerate flavor where [single] and
/// [many] are `null`: type wrappers return the bare type and the value/callable
/// helpers fall back to the plain synchronous expression, so callers can branch
/// purely on [isReactive].
class JavaReactiveFlavor {
  /// Deferred-single wrapper type name (`Mono`/`Single`/`Uni`), or `null` for
  /// blocking.
  final String? single;

  /// Deferred-many wrapper type name (`Flux`/`Observable`/`Multi`), used only
  /// for subscriptions, or `null` for blocking.
  final String? many;

  /// Fully-qualified imports the emitted file needs for this flavor.
  final List<String> imports;

  const JavaReactiveFlavor._(this.single, this.many, this.imports);

  bool get isReactive => single != null;

  /// Just the deferred-single import(s) — for files that reference only the
  /// single type (the adapter interface and default adapter), avoiding an
  /// unused import of the many type.
  List<String> get singleImports =>
      imports.isEmpty ? const [] : [imports.first];

  /// Lifts an already-computed value expression into the deferred-single type.
  /// Blocking returns the expression unchanged.
  ///   Mono.just(expr) / Single.just(expr) / Uni.createFrom().item(expr)
  String wrapValue(String expr) {
    switch (single) {
      case 'Mono':
        return 'Mono.just($expr)';
      case 'Single':
        return 'Single.just($expr)';
      case 'Uni':
        return 'Uni.createFrom().item($expr)';
      default:
        return expr;
    }
  }

  /// Lifts a `Callable`/`Supplier` lambda (deferred work) into the
  /// deferred-single type. Blocking just invokes the supplier.
  ///   Mono.fromCallable(lambda) / Single.fromCallable(lambda)
  ///   / Uni.createFrom().item(lambda)
  String wrapCallable(String lambda) {
    switch (single) {
      case 'Mono':
        return 'Mono.fromCallable($lambda)';
      case 'Single':
        return 'Single.fromCallable($lambda)';
      case 'Uni':
        return 'Uni.createFrom().item($lambda)';
      default:
        return '($lambda).get()';
    }
  }

  /// Lifts a `Throwable` expression into a failed deferred-single.
  ///   Mono.error(t) / Single.error(t) / Uni.createFrom().failure(t)
  String error(String throwableExpr) {
    switch (single) {
      case 'Mono':
        return 'Mono.error($throwableExpr)';
      case 'Single':
        return 'Single.error($throwableExpr)';
      case 'Uni':
        return 'Uni.createFrom().failure($throwableExpr)';
      default:
        return 'throw new RuntimeException($throwableExpr)';
    }
  }

  /// Bridges a `CompletableFuture`/`CompletionStage` expression into the
  /// deferred-single type — the universal adapter transport seam.
  ///   Mono.fromFuture(f) / Single.fromCompletionStage(f)
  ///   / Uni.createFrom().completionStage(f)
  String bridgeFuture(String futureExpr) {
    switch (single) {
      case 'Mono':
        return 'Mono.fromFuture($futureExpr)';
      case 'Single':
        return 'Single.fromCompletionStage($futureExpr)';
      case 'Uni':
        return 'Uni.createFrom().completionStage($futureExpr)';
      default:
        return futureExpr;
    }
  }

  /// `src.map(fn)` — identical across all reactive libraries. [fn] must be a
  /// complete expression (e.g. a method reference or single-expression lambda).
  String mapTo(String src, String fn) => '$src.map($fn)';

  /// Opens a multi-line `map` with a lambda block: `src.map(param -> {`.
  /// The caller is responsible for emitting the body and closing with `})`.
  String mapOpen(String src, String param) => '$src.map($param -> {';

  /// Opens a multi-line error-recovery with a lambda block. The caller emits
  /// the body and closes with `})`.
  String onErrorResumeOpen(String src, String param) {
    switch (single) {
      case 'Mono':
        return '$src.onErrorResume($param -> {';
      case 'Single':
        return '$src.onErrorResumeNext($param -> {';
      case 'Uni':
        return '$src.onFailure().recoverWithUni($param -> {';
      default:
        return src;
    }
  }

  /// `src.flatMap(fn)` — identical across all reactive libraries.
  String flatMap(String src, String fn) => '$src.flatMap($fn)';

  /// Error-recovery combinator. Reactor/RxJava expose `onErrorResume*`; Mutiny
  /// diverges with `onFailure().recoverWithUni`.
  String onErrorResume(String src, String fallbackLambda) {
    switch (single) {
      case 'Mono':
        return '$src.onErrorResume($fallbackLambda)';
      case 'Single':
        return '$src.onErrorResumeNext($fallbackLambda)';
      case 'Uni':
        return '$src.onFailure().recoverWithUni($fallbackLambda)';
      default:
        return src;
    }
  }

  /// Builds a deferred-many stream from an imperative emitter callback,
  /// bridging the push-based [GraphLinkSubscriptionHandler] into the library's
  /// stream type. [emitterParam] is the lambda parameter name; [body] is the
  /// emitter wiring (must register a listener that calls [emitNext]/[emitComplete]/
  /// [emitError]).
  ///   Flux.create(emitter -> { body })
  ///   Observable.create(emitter -> { body })
  ///   Multi.createFrom().emitter(emitter -> { body })
  String createMany(String emitterParam, String body) {
    switch (many) {
      case 'Flux':
        return 'Flux.create($emitterParam -> {\n$body\n})';
      case 'Observable':
        return 'Observable.create($emitterParam -> {\n$body\n})';
      case 'Multi':
        return 'Multi.createFrom().emitter($emitterParam -> {\n$body\n})';
      default:
        return body;
    }
  }

  String emitNext(String emitter, String value) {
    switch (many) {
      case 'Flux':
        return '$emitter.next($value);';
      case 'Multi':
        return '$emitter.emit($value);';
      default: // Observable
        return '$emitter.onNext($value);';
    }
  }

  String emitComplete(String emitter) {
    switch (many) {
      case 'Observable':
        return '$emitter.onComplete();';
      default: // Flux / Multi
        return '$emitter.complete();';
    }
  }

  String emitError(String emitter, String err) {
    switch (many) {
      case 'Flux':
        return '$emitter.error($err);';
      case 'Multi':
        return '$emitter.fail($err);';
      default: // Observable
        return '$emitter.onError($err);';
    }
  }

  static const JavaReactiveFlavor blocking =
      JavaReactiveFlavor._(null, null, []);

  static const JavaReactiveFlavor reactor = JavaReactiveFlavor._(
    'Mono',
    'Flux',
    ['reactor.core.publisher.Mono', 'reactor.core.publisher.Flux'],
  );

  static const JavaReactiveFlavor rxjava3 = JavaReactiveFlavor._(
    'Single',
    'Observable',
    [
      'io.reactivex.rxjava3.core.Single',
      'io.reactivex.rxjava3.core.Observable',
    ],
  );

  static const JavaReactiveFlavor mutiny = JavaReactiveFlavor._(
    'Uni',
    'Multi',
    ['io.smallrye.mutiny.Uni', 'io.smallrye.mutiny.Multi'],
  );

  factory JavaReactiveFlavor.of(JavaAsyncStyle style) {
    switch (style) {
      case JavaAsyncStyle.blocking:
        return blocking;
      case JavaAsyncStyle.reactor:
        return reactor;
      case JavaAsyncStyle.rxjava3:
        return rxjava3;
      case JavaAsyncStyle.mutiny:
        return mutiny;
    }
  }
}
