import 'package:graphlink/src/persisted_queries.dart';

const goUtil = r'''
// Ptr returns a pointer to v, for optional (nullable) fields and arguments.
func Ptr[T any](v T) *T { return &v }

func glIsNull(data []byte) bool {
	trimmed := bytes.TrimSpace(data)
	return len(trimmed) == 0 || string(trimmed) == "null"
}

func glDecodeList[T any](raw json.RawMessage, elem func(json.RawMessage) (T, error)) ([]T, error) {
	if glIsNull(raw) {
		return nil, nil
	}
	var items []json.RawMessage
	if err := json.Unmarshal(raw, &items); err != nil {
		return nil, err
	}
	result := make([]T, len(items))
	for i, item := range items {
		value, err := elem(item)
		if err != nil {
			return nil, err
		}
		result[i] = value
	}
	return result, nil
}

func glMapSlice[A, B any](in []A, fn func(A) B) []B {
	if in == nil {
		return nil
	}
	out := make([]B, len(in))
	for i, item := range in {
		out[i] = fn(item)
	}
	return out
}

func glMapPtr[A, B any](in *A, fn func(A) B) *B {
	if in == nil {
		return nil
	}
	mapped := fn(*in)
	return &mapped
}

func glMergeVariables(dst map[string]any, src any) {
	encoded, err := json.Marshal(src)
	if err != nil {
		return
	}
	var fields map[string]any
	if err := json.Unmarshal(encoded, &fields); err != nil {
		return
	}
	for key, value := range fields {
		dst[key] = value
	}
}

func glUUID() string {
	raw := make([]byte, 16)
	for i := range raw {
		raw[i] = byte(rand.Intn(256))
	}
	encoded := hex.EncodeToString(raw)
	return encoded[0:8] + "-" + encoded[8:12] + "-" + encoded[12:16] + "-" + encoded[16:20] + "-" + encoded[20:32]
}
''';

const goException = r'''
// GraphLinkException wraps the GraphQL errors returned by the server.
type GraphLinkException struct {
	Errors []GraphLinkError
}

func (e *GraphLinkException) Error() string {
	messages := make([]string, len(e.Errors))
	for i, err := range e.Errors {
		messages[i] = err.Message
	}
	if len(messages) == 0 {
		return "GraphQL request failed"
	}
	return "GraphQL errors: " + strings.Join(messages, "; ")
}

// GraphLinkEvent is one item of a subscription stream. A non-nil Err does not
// end the stream: the channel only closes when the context is cancelled or the
// server completes the subscription.
type GraphLinkEvent[T any] struct {
	Data T
	Err  error
}
''';

const goCache = r'''
// GraphLinkLock serialises the read-modify-write cycles on one cache tag.
type GraphLinkLock struct {
	mu sync.Mutex
}

func (l *GraphLinkLock) Synchronized(fn func() error) error {
	l.mu.Lock()
	defer l.mu.Unlock()
	return fn()
}

// GraphLinkTagLocks hands out the lock for a tag, creating it on first use.
type GraphLinkTagLocks struct {
	mu    sync.Mutex
	locks map[string]*GraphLinkLock
}

func NewGraphLinkTagLocks(tags []string) *GraphLinkTagLocks {
	locks := &GraphLinkTagLocks{locks: map[string]*GraphLinkLock{}}
	for _, tag := range tags {
		locks.locks[tag] = &GraphLinkLock{}
	}
	return locks
}

func (t *GraphLinkTagLocks) For(tag string) *GraphLinkLock {
	t.mu.Lock()
	defer t.mu.Unlock()
	lock, ok := t.locks[tag]
	if !ok {
		lock = &GraphLinkLock{}
		t.locks[tag] = lock
	}
	return lock
}

type GraphLinkCacheEntry struct {
	Data   string `json:"data"`
	Expiry int64  `json:"expiry"`
	Stale  bool   `json:"-"`
}

func NewGraphLinkCacheEntry(data string, expiry int64) GraphLinkCacheEntry {
	return GraphLinkCacheEntry{Data: data, Expiry: expiry}
}

func DecodeGraphLinkCacheEntry(raw string) (*GraphLinkCacheEntry, error) {
	var entry GraphLinkCacheEntry
	if err := json.Unmarshal([]byte(raw), &entry); err != nil {
		return nil, err
	}
	return &entry, nil
}

func (e GraphLinkCacheEntry) Encode() (string, error) {
	encoded, err := json.Marshal(e)
	return string(encoded), err
}

func (e GraphLinkCacheEntry) IsExpired() bool {
	return time.Now().UnixMilli() > e.Expiry
}

func (e GraphLinkCacheEntry) AsStale() *GraphLinkCacheEntry {
	e.Stale = true
	return &e
}

type GraphLinkTagEntry struct {
	keys map[string]struct{}
	order []string
}

func NewGraphLinkTagEntry() *GraphLinkTagEntry {
	return &GraphLinkTagEntry{keys: map[string]struct{}{}}
}

func DecodeGraphLinkTagEntry(raw string) (*GraphLinkTagEntry, error) {
	var parsed struct {
		Keys []string `json:"keys"`
	}
	if err := json.Unmarshal([]byte(raw), &parsed); err != nil {
		return nil, err
	}
	entry := NewGraphLinkTagEntry()
	for _, key := range parsed.Keys {
		entry.Add(key)
	}
	return entry, nil
}

func (e *GraphLinkTagEntry) Encode() (string, error) {
	keys := e.Keys()
	encoded, err := json.Marshal(map[string][]string{"keys": keys})
	return string(encoded), err
}

func (e *GraphLinkTagEntry) Add(key string) {
	if _, ok := e.keys[key]; ok {
		return
	}
	e.keys[key] = struct{}{}
	e.order = append(e.order, key)
}

func (e *GraphLinkTagEntry) Remove(key string) {
	if _, ok := e.keys[key]; !ok {
		return
	}
	delete(e.keys, key)
	for i, existing := range e.order {
		if existing == key {
			e.order = append(e.order[:i], e.order[i+1:]...)
			break
		}
	}
}

func (e *GraphLinkTagEntry) Keys() []string {
	keys := make([]string, len(e.order))
	copy(keys, e.order)
	return keys
}

func (e *GraphLinkTagEntry) Len() int { return len(e.keys) }

// GraphLinkCacheStore persists cache entries. Implement it to plug in Redis,
// disk, or any other backend.
type GraphLinkCacheStore interface {
	Set(ctx context.Context, key, value string) error
	Get(ctx context.Context, key string) (value string, found bool, err error)
	Invalidate(ctx context.Context, key string) error
	InvalidateAll(ctx context.Context) error
}

type InMemoryGraphLinkCacheStore struct {
	mu    sync.RWMutex
	store map[string]string
}

func NewInMemoryGraphLinkCacheStore() *InMemoryGraphLinkCacheStore {
	return &InMemoryGraphLinkCacheStore{store: map[string]string{}}
}

func (s *InMemoryGraphLinkCacheStore) Set(ctx context.Context, key, value string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.store[key] = value
	return nil
}

func (s *InMemoryGraphLinkCacheStore) Get(ctx context.Context, key string) (string, bool, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	value, ok := s.store[key]
	return value, ok, nil
}

func (s *InMemoryGraphLinkCacheStore) Invalidate(ctx context.Context, key string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.store, key)
	return nil
}

func (s *InMemoryGraphLinkCacheStore) InvalidateAll(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.store = map[string]string{}
	return nil
}
''';

const goPartialQuery = r'''
type GraphLinkPartialQuery struct {
	Query                string
	Variables            map[string]any
	TTL                  int
	Tags                 []string
	OperationName        string
	ElementKey           string
	FragmentNames        []string
	ArgumentDeclarations []string
	StaleIfOffline       bool
	CacheKey             string
}

// NewGraphLinkPartialQuery derives the cache key; queries with a zero TTL are never cached.
func NewGraphLinkPartialQuery(p GraphLinkPartialQuery) GraphLinkPartialQuery {
	if p.TTL > 0 {
		p.CacheKey = ComputeGraphLinkCacheKey(p.OperationName, p.Variables)
	}
	return p
}

func ComputeGraphLinkCacheKey(operationName string, variables map[string]any) string {
	encoded, _ := json.Marshal(variables)
	hash := fnv.New32a()
	_, _ = hash.Write([]byte(operationName + ":" + string(encoded)))
	return fmt.Sprintf("%08x", hash.Sum32())
}
''';

String goResolverBase({
  required bool operationNameAsParameter,
  required bool persistedQueries,
}) {
  final opParam = operationNameAsParameter ? ', operationName string' : '';
  final opArg = operationNameAsParameter ? ', glOperationName(body)' : '';
  final base = r'''
const glTagKeyPrefix = "__tag__"

// GraphLinkAdapter sends one serialised GraphQL request and returns the raw response body.
type GraphLinkAdapter func(ctx context.Context, payload string__OP_PARAM__) (string, error)

type GraphLinkResolverBase struct {
	store                GraphLinkCacheStore
	tagLocks             *GraphLinkTagLocks
	fragMap              map[string]string
	adapter              GraphLinkAdapter
	getAdapter           GraphLinkAdapter
	hashes               sync.Map
	persistedUnsupported atomic.Bool
	getUnsupported       atomic.Bool
}

func (r *GraphLinkResolverBase) init(store GraphLinkCacheStore, locks *GraphLinkTagLocks, adapter, getAdapter GraphLinkAdapter, fragmentMap map[string]string) {
	r.store = store
	r.tagLocks = locks
	r.adapter = adapter
	r.getAdapter = getAdapter
	r.fragMap = fragmentMap
}

func (p GraphLinkPayload) glBody() map[string]any {
	variables := p.Variables
	if variables == nil {
		variables = map[string]any{}
	}
	return map[string]any{"query": p.Query, "operationName": p.OperationName, "variables": variables}
}

__OPERATION_NAME_HELPER__
func (r *GraphLinkResolverBase) glSend(ctx context.Context, body map[string]any) (string, error) {
	encoded, err := json.Marshal(body)
	if err != nil {
		return "", err
	}
	return r.adapter(ctx, string(encoded)__OP_ARG__)
}

func (r *GraphLinkResolverBase) assembleQuery(query string, fragmentNames []string) string {
	var builder strings.Builder
	builder.WriteString(query)
	for _, name := range fragmentNames {
		if fragment, ok := r.fragMap[name]; ok {
			builder.WriteString(" ")
			builder.WriteString(fragment)
		}
	}
	return builder.String()
}
__CALL_ADAPTER__
func glDecodeFull[T GraphLinkFullResponse](value any) (T, error) {
	var result T
	encoded, err := json.Marshal(value)
	if err != nil {
		return result, err
	}
	err = json.Unmarshal(encoded, &result)
	return result, err
}

func glExecuteFull[T GraphLinkFullResponse](ctx context.Context, r *GraphLinkResolverBase, query string, fragmentNames []string, operationName string, variables map[string]any) (T, error) {
	var result T
	payload := GraphLinkPayload{Query: r.assembleQuery(query, fragmentNames), OperationName: operationName, Variables: variables}
	text, err := r.glCallAdapter(ctx, payload)
	if err != nil {
		return result, err
	}
	err = json.Unmarshal([]byte(text), &result)
	return result, err
}

func glExecuteData[T GraphLinkFullResponse](ctx context.Context, r *GraphLinkResolverBase, query string, fragmentNames []string, operationName string, variables map[string]any) (T, error) {
	result, err := glExecuteFull[T](ctx, r, query, fragmentNames, operationName, variables)
	if err != nil {
		return result, err
	}
	if errs := result.GetErrors(); len(errs) > 0 {
		return result, &GraphLinkException{Errors: errs}
	}
	return result, nil
}

func glRemainingQueries(partialQueries []GraphLinkPartialQuery, responseMap map[string]json.RawMessage) []GraphLinkPartialQuery {
	var remaining []GraphLinkPartialQuery
	for _, query := range partialQueries {
		if _, ok := responseMap[query.ElementKey]; !ok {
			remaining = append(remaining, query)
		}
	}
	return remaining
}

func glExecuteCached[T GraphLinkFullResponse](ctx context.Context, r *GraphLinkResolverBase, partialQueries []GraphLinkPartialQuery, operationName, directives string, captureErrors bool) (T, error) {
	var zero T
	responseMap := map[string]json.RawMessage{}
	staleData := map[string]json.RawMessage{}
	for _, query := range partialQueries {
		if query.TTL <= 0 {
			continue
		}
		entry, err := r.getFromCache(ctx, query.CacheKey, query.Tags, query.StaleIfOffline)
		if err != nil || entry == nil {
			continue
		}
		if entry.Stale {
			staleData[query.ElementKey] = json.RawMessage(entry.Data)
		} else {
			responseMap[query.ElementKey] = json.RawMessage(entry.Data)
		}
	}
	remaining := glRemainingQueries(partialQueries, responseMap)
	if len(remaining) == 0 {
		return glDecodeFull[T](map[string]any{"data": responseMap})
	}
	payload := r.buildPayload(remaining, operationName, directives)
	result, err := func() (T, error) {
		text, err := r.glCallAdapter(ctx, payload)
		if err != nil {
			return zero, err
		}
		return glParseAndCache[T](ctx, r, text, responseMap, remaining, captureErrors)
	}()
	if err == nil {
		return result, nil
	}
	for key, value := range staleData {
		responseMap[key] = value
	}
	if len(glRemainingQueries(partialQueries, responseMap)) > 0 {
		return zero, err
	}
	return glDecodeFull[T](map[string]any{"data": responseMap})
}

func glParseAndCache[T GraphLinkFullResponse](ctx context.Context, r *GraphLinkResolverBase, text string, cachedResponse map[string]json.RawMessage, remaining []GraphLinkPartialQuery, captureErrors bool) (T, error) {
	var zero T
	var result struct {
		Data   map[string]json.RawMessage `json:"data"`
		Errors json.RawMessage            `json:"errors"`
	}
	if err := json.Unmarshal([]byte(text), &result); err != nil {
		return zero, err
	}
	dataMap := result.Data
	hasData := dataMap != nil
	if dataMap == nil {
		dataMap = map[string]json.RawMessage{}
	}
	for _, query := range remaining {
		element, ok := dataMap[query.ElementKey]
		if query.TTL <= 0 || !ok || glIsNull(element) {
			continue
		}
		entry := NewGraphLinkCacheEntry(string(element), time.Now().UnixMilli()+int64(query.TTL)*1000)
		if encoded, err := entry.Encode(); err == nil {
			_ = r.store.Set(ctx, query.CacheKey, encoded)
		}
		if len(query.Tags) > 0 {
			_ = r.addKeyToTags(ctx, query.CacheKey, query.Tags)
		}
	}
	for key, value := range cachedResponse {
		dataMap[key] = value
	}
	full := map[string]any{"data": nil}
	if hasData {
		full["data"] = dataMap
	}
	if !glIsNull(result.Errors) {
		full["errors"] = result.Errors
	}
	parsed, err := glDecodeFull[T](full)
	if err != nil {
		return zero, err
	}
	if captureErrors {
		return parsed, nil
	}
	if errs := parsed.GetErrors(); len(errs) > 0 {
		return zero, &GraphLinkException{Errors: errs}
	}
	return parsed, nil
}

func (r *GraphLinkResolverBase) buildPayload(partQueries []GraphLinkPartialQuery, operationName, directives string) GraphLinkPayload {
	variables := map[string]any{}
	var arguments, fragmentNames []string
	seenArguments := map[string]struct{}{}
	seenFragments := map[string]struct{}{}
	for _, query := range partQueries {
		for key, value := range query.Variables {
			variables[key] = value
		}
		for _, declaration := range query.ArgumentDeclarations {
			if _, ok := seenArguments[declaration]; !ok {
				seenArguments[declaration] = struct{}{}
				arguments = append(arguments, declaration)
			}
		}
		for _, name := range query.FragmentNames {
			if _, ok := seenFragments[name]; !ok {
				seenFragments[name] = struct{}{}
				fragmentNames = append(fragmentNames, name)
			}
		}
	}
	var builder strings.Builder
	builder.WriteString("query " + operationName)
	if len(arguments) > 0 {
		builder.WriteString("(" + strings.Join(arguments, ", ") + ")")
	}
	if directives != "" {
		builder.WriteString(directives)
	}
	builder.WriteString("{")
	for _, query := range partQueries {
		builder.WriteString(query.Query)
		builder.WriteString(" ")
	}
	builder.WriteString("}")
	for _, name := range fragmentNames {
		builder.WriteString(r.fragMap[name])
	}
	return GraphLinkPayload{Query: builder.String(), OperationName: operationName, Variables: variables}
}

func (r *GraphLinkResolverBase) getFromCache(ctx context.Context, key string, tags []string, staleIfOffline bool) (*GraphLinkCacheEntry, error) {
	raw, found, err := r.store.Get(ctx, key)
	if err != nil || !found {
		return nil, err
	}
	entry, err := DecodeGraphLinkCacheEntry(raw)
	if err != nil {
		return nil, err
	}
	if !entry.IsExpired() {
		return entry, nil
	}
	if staleIfOffline {
		return entry.AsStale(), nil
	}
	_ = r.store.Invalidate(ctx, key)
	if len(tags) > 0 {
		_ = r.removeKeyFromTags(ctx, key, tags)
	}
	return nil, nil
}

func (r *GraphLinkResolverBase) invalidateByTags(ctx context.Context, tags []string) error {
	for _, tag := range tags {
		tagKey := glTagKeyPrefix + tag
		err := r.tagLocks.For(tag).Synchronized(func() error {
			data, found, err := r.store.Get(ctx, tagKey)
			if err != nil || !found {
				return err
			}
			entry, err := DecodeGraphLinkTagEntry(data)
			if err != nil {
				return err
			}
			for _, key := range entry.Keys() {
				if err := r.store.Invalidate(ctx, key); err != nil {
					return err
				}
			}
			return r.store.Invalidate(ctx, tagKey)
		})
		if err != nil {
			return err
		}
	}
	return nil
}

func (r *GraphLinkResolverBase) addKeyToTags(ctx context.Context, key string, tags []string) error {
	for _, tag := range tags {
		tagKey := glTagKeyPrefix + tag
		err := r.tagLocks.For(tag).Synchronized(func() error {
			data, found, err := r.store.Get(ctx, tagKey)
			if err != nil {
				return err
			}
			entry := NewGraphLinkTagEntry()
			if found {
				if entry, err = DecodeGraphLinkTagEntry(data); err != nil {
					return err
				}
			}
			entry.Add(key)
			encoded, err := entry.Encode()
			if err != nil {
				return err
			}
			return r.store.Set(ctx, tagKey, encoded)
		})
		if err != nil {
			return err
		}
	}
	return nil
}

func (r *GraphLinkResolverBase) removeKeyFromTags(ctx context.Context, key string, tags []string) error {
	for _, tag := range tags {
		tagKey := glTagKeyPrefix + tag
		err := r.tagLocks.For(tag).Synchronized(func() error {
			data, found, err := r.store.Get(ctx, tagKey)
			if err != nil || !found {
				return err
			}
			entry, err := DecodeGraphLinkTagEntry(data)
			if err != nil {
				return err
			}
			entry.Remove(key)
			if entry.Len() == 0 {
				return r.store.Invalidate(ctx, tagKey)
			}
			encoded, err := entry.Encode()
			if err != nil {
				return err
			}
			return r.store.Set(ctx, tagKey, encoded)
		})
		if err != nil {
			return err
		}
	}
	return nil
}
''';
  const operationNameHelper = r'''
func glOperationName(body map[string]any) string {
	name, _ := body["operationName"].(string)
	return name
}
''';
  const plainCallAdapter = r'''
func (r *GraphLinkResolverBase) glCallAdapter(ctx context.Context, payload GraphLinkPayload) (string, error) {
	return r.glSend(ctx, payload.glBody())
}
''';
  return base
      .replaceAll('__OP_PARAM__', opParam)
      .replaceAll('__OP_ARG__', opArg)
      .replaceAll('__OPERATION_NAME_HELPER__', operationNameAsParameter ? operationNameHelper : '')
      .replaceAll('__CALL_ADAPTER__', persistedQueries ? '' : plainCallAdapter);
}

String goPersistedQueries({
  required bool operationNameAsParameter,
  required bool useGet,
}) {
  final opArg = operationNameAsParameter ? ', glOperationName(body)' : '';
  final common = r'''
const glPersistedMinQueryLength = __MIN__
const glPersistedNotFound = "PersistedQueryNotFound"
const glPersistedNotSupported = "PersistedQueryNotSupported"

func glPersistedExtensions(hash string) map[string]any {
	return map[string]any{"persistedQuery": map[string]any{"version": 1, "sha256Hash": hash}}
}

func glPersistedFailure(response string) string {
	if !strings.Contains(response, "PersistedQuery") && !strings.Contains(response, "PERSISTED_QUERY") {
		return ""
	}
	var decoded struct {
		Errors []struct {
			Message    string         `json:"message"`
			Extensions map[string]any `json:"extensions"`
		} `json:"errors"`
	}
	if err := json.Unmarshal([]byte(response), &decoded); err != nil {
		return ""
	}
	for _, e := range decoded.Errors {
		code, _ := e.Extensions["code"].(string)
		if e.Message == glPersistedNotFound || code == "PERSISTED_QUERY_NOT_FOUND" {
			return glPersistedNotFound
		}
		if e.Message == glPersistedNotSupported || code == "PERSISTED_QUERY_NOT_SUPPORTED" {
			return glPersistedNotSupported
		}
	}
	return ""
}

func (r *GraphLinkResolverBase) glHash(query string) string {
	if cached, ok := r.hashes.Load(query); ok {
		return cached.(string)
	}
	sum := sha256.Sum256([]byte(query))
	hash := hex.EncodeToString(sum[:])
	r.hashes.Store(query, hash)
	return hash
}

func (r *GraphLinkResolverBase) glCallAdapter(ctx context.Context, payload GraphLinkPayload) (string, error) {
	if r.persistedUnsupported.Load() || len(payload.Query) <= glPersistedMinQueryLength {
		return r.glSend(ctx, payload.glBody())
	}
	extensions := glPersistedExtensions(r.glHash(payload.Query))
	hashOnly := map[string]any{"operationName": payload.OperationName, "variables": payload.glBody()["variables"], "extensions": extensions}
	response, err := __SEND_HASH_ONLY__
	if err != nil {
		return "", err
	}
	failure := glPersistedFailure(response)
	if failure == "" {
		return response, nil
	}
	body := payload.glBody()
	if failure == glPersistedNotSupported {
		r.persistedUnsupported.Store(true)
	} else {
		body["extensions"] = extensions
	}
	return r.glSend(ctx, body)
}
''';
  const getRuntime = r'''

// GraphLinkGetNotSupported is returned by a GET adapter when the server refuses GET requests.
type GraphLinkGetNotSupported struct {
	Message string
}

func (e *GraphLinkGetNotSupported) Error() string {
	if e.Message == "" {
		return "GraphLinkGetNotSupported"
	}
	return "GraphLinkGetNotSupported: " + e.Message
}

// GraphLinkGetQueryParameters turns a serialised hash-only request body into GET query parameters.
func GraphLinkGetQueryParameters(payload string) (url.Values, error) {
	var body map[string]json.RawMessage
	if err := json.Unmarshal([]byte(payload), &body); err != nil {
		return nil, err
	}
	params := url.Values{}
	if name := body["operationName"]; !glIsNull(name) {
		var operationName string
		if err := json.Unmarshal(name, &operationName); err == nil {
			params.Set("operationName", operationName)
		}
	}
	var variables map[string]json.RawMessage
	if json.Unmarshal(body["variables"], &variables) == nil && len(variables) > 0 {
		params.Set("variables", string(body["variables"]))
	}
	params.Set("extensions", string(body["extensions"]))
	return params, nil
}

func (r *GraphLinkResolverBase) glSendHashOnly(ctx context.Context, payload GraphLinkPayload, body map[string]any) (string, error) {
	if r.getUnsupported.Load() || strings.HasPrefix(payload.Query, "mutation") {
		return r.glSend(ctx, body)
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return "", err
	}
	response, err := r.getAdapter(ctx, string(encoded)__OP_ARG__)
	if err == nil {
		return response, nil
	}
	var notSupported *GraphLinkGetNotSupported
	if !errors.As(err, &notSupported) {
		return "", err
	}
	r.getUnsupported.Store(true)
	return r.glSend(ctx, body)
}
''';
  final sendHashOnly = useGet ? 'r.glSendHashOnly(ctx, payload, hashOnly)' : 'r.glSend(ctx, hashOnly)';
  return [
    common.replaceAll('__MIN__', '$persistedQueryMinLength').replaceAll('__SEND_HASH_ONLY__', sendHashOnly),
    if (useGet) getRuntime.replaceAll('__OP_ARG__', opArg.replaceAll('body', 'body')),
  ].join('\n');
}

const goUploads = r'''
type UploadProgressCallback func(sent, total int64)

type GLUploadConverter func(upload GLUpload) any

type GLMultipartAdapter func(ctx context.Context, parts map[string]any, onProgress UploadProgressCallback) (string, error)

// GLUpload is one file to upload. Length is -1 when unknown.
type GLUpload struct {
	Reader   io.Reader
	Length   int64
	Filename string
	MimeType string
}

func NewGLUpload(reader io.Reader, filename string) GLUpload {
	return GLUpload{Reader: reader, Length: -1, Filename: filename, MimeType: "application/octet-stream"}
}

func GLUploadFromBytes(data []byte, filename, mimeType string) GLUpload {
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}
	return GLUpload{Reader: bytes.NewReader(data), Length: int64(len(data)), Filename: filename, MimeType: mimeType}
}

// GLUploadFromFile opens path; the adapter closes the file once it has been sent.
func GLUploadFromFile(path, mimeType string) (GLUpload, error) {
	file, err := os.Open(path)
	if err != nil {
		return GLUpload{}, err
	}
	info, err := file.Stat()
	if err != nil {
		_ = file.Close()
		return GLUpload{}, err
	}
	if mimeType == "" {
		mimeType = "application/octet-stream"
	}
	return GLUpload{Reader: file, Length: info.Size(), Filename: filepath.Base(path), MimeType: mimeType}, nil
}
''';

const goUploadDefaultConverter = r'''
// DefaultUploadConverter passes the GLUpload through unchanged; the HTTP adapter's MultipartCall understands it.
func DefaultUploadConverter(upload GLUpload) any { return upload }
''';

const goWsMessageTypes = r'''
const (
	GraphqlWsConnectionInit = "connection_init"
	GraphqlWsConnectionAck  = "connection_ack"
	GraphqlWsSubscribe      = "subscribe"
	GraphqlWsPing           = "ping"
	GraphqlWsPong           = "pong"
	GraphqlWsNext           = "next"
	GraphqlWsError          = "error"
	GraphqlWsComplete       = "complete"
)
''';

const goWebSocketAdapter = r'''
// GraphLinkWebSocketAdapter is the transport under subscriptions (graphql-transport-ws).
type GraphLinkWebSocketAdapter interface {
	Connect(ctx context.Context) error
	SendMessage(ctx context.Context, message string) error
	Close() error
	// ConnectionInitPayload is sent with connection_init; return headers or an auth token here.
	ConnectionInitPayload(ctx context.Context) (map[string]any, error)
	// SetMessageHandler registers the single consumer of incoming text frames.
	SetMessageHandler(handler func(message string))
	// SetReconnectHandler registers the callback fired after a successful reconnect.
	SetReconnectHandler(handler func())
}
''';

const goSubscriptionHandler = r'''
type GraphLinkRawEvent struct {
	Data json.RawMessage
	Err  error
}

type glSubscription struct {
	id      string
	payload GraphLinkPayload
	events  chan GraphLinkRawEvent
	done    chan struct{}
	mu      sync.RWMutex
	closed  bool
	once    sync.Once
}

func (s *glSubscription) emit(event GraphLinkRawEvent) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if s.closed {
		return
	}
	select {
	case s.events <- event:
	case <-s.done:
	}
}

func (s *glSubscription) finish() {
	s.once.Do(func() {
		close(s.done)
		s.mu.Lock()
		s.closed = true
		close(s.events)
		s.mu.Unlock()
	})
}

type glWsMessage struct {
	ID      string          `json:"id"`
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

const glHandshakeTimeout = 30 * time.Second

type GraphLinkSubscriptionHandler struct {
	adapter      GraphLinkWebSocketAdapter
	mu           sync.Mutex
	subs         map[string]*glSubscription
	connMu       sync.Mutex
	acknowledged bool
	ackCh        chan struct{}
}

func NewGraphLinkSubscriptionHandler(adapter GraphLinkWebSocketAdapter) *GraphLinkSubscriptionHandler {
	handler := &GraphLinkSubscriptionHandler{
		adapter: adapter,
		subs:    map[string]*glSubscription{},
		ackCh:   make(chan struct{}, 1),
	}
	adapter.SetMessageHandler(handler.onMessage)
	adapter.SetReconnectHandler(handler.onReconnect)
	return handler
}

// Handle opens a subscription for payload. The returned channel closes when ctx is
// cancelled or the server completes the subscription.
func (h *GraphLinkSubscriptionHandler) Handle(ctx context.Context, payload GraphLinkPayload) <-chan GraphLinkRawEvent {
	sub := &glSubscription{
		id:      glUUID(),
		payload: payload,
		events:  make(chan GraphLinkRawEvent, 64),
		done:    make(chan struct{}),
	}
	h.mu.Lock()
	h.subs[sub.id] = sub
	h.mu.Unlock()

	go func() {
		if err := h.ensureConnected(ctx); err != nil {
			sub.emit(GraphLinkRawEvent{Err: err})
			return
		}
		if err := h.sendSubscribe(ctx, sub); err != nil {
			sub.emit(GraphLinkRawEvent{Err: err})
		}
	}()
	go func() {
		select {
		case <-ctx.Done():
			h.cancel(sub)
		case <-sub.done:
		}
	}()
	return sub.events
}

func (h *GraphLinkSubscriptionHandler) ensureConnected(ctx context.Context) error {
	h.connMu.Lock()
	defer h.connMu.Unlock()
	if h.acknowledged {
		return nil
	}
	if err := h.adapter.Connect(ctx); err != nil {
		return err
	}
	return h.handshake(ctx)
}

func (h *GraphLinkSubscriptionHandler) handshake(ctx context.Context) error {
	select {
	case <-h.ackCh:
	default:
	}
	initPayload, err := h.adapter.ConnectionInitPayload(ctx)
	if err != nil {
		return err
	}
	message := map[string]any{"type": GraphqlWsConnectionInit}
	if initPayload != nil {
		message["payload"] = initPayload
	}
	encoded, err := json.Marshal(message)
	if err != nil {
		return err
	}
	if err := h.adapter.SendMessage(ctx, string(encoded)); err != nil {
		return err
	}
	select {
	case <-h.ackCh:
		h.acknowledged = true
		return nil
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(glHandshakeTimeout):
		return errors.New("WebSocket handshake timed out waiting for connection_ack")
	}
}

func (h *GraphLinkSubscriptionHandler) sendSubscribe(ctx context.Context, sub *glSubscription) error {
	message := map[string]any{
		"id":   sub.id,
		"type": GraphqlWsSubscribe,
		"payload": map[string]any{
			"query":         sub.payload.Query,
			"operationName": sub.payload.OperationName,
			"variables":     sub.payload.Variables,
		},
	}
	encoded, err := json.Marshal(message)
	if err != nil {
		return err
	}
	return h.adapter.SendMessage(ctx, string(encoded))
}

func (h *GraphLinkSubscriptionHandler) onReconnect() {
	go func() {
		h.connMu.Lock()
		h.acknowledged = false
		h.mu.Lock()
		subs := make([]*glSubscription, 0, len(h.subs))
		for _, sub := range h.subs {
			subs = append(subs, sub)
		}
		h.mu.Unlock()
		if len(subs) == 0 {
			h.connMu.Unlock()
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), glHandshakeTimeout)
		defer cancel()
		err := h.handshake(ctx)
		h.connMu.Unlock()
		for _, sub := range subs {
			if err != nil {
				sub.emit(GraphLinkRawEvent{Err: err})
				continue
			}
			if sendErr := h.sendSubscribe(ctx, sub); sendErr != nil {
				sub.emit(GraphLinkRawEvent{Err: sendErr})
			}
		}
	}()
}

func (h *GraphLinkSubscriptionHandler) cancel(sub *glSubscription) {
	h.mu.Lock()
	_, active := h.subs[sub.id]
	delete(h.subs, sub.id)
	h.mu.Unlock()
	sub.finish()
	if !active {
		return
	}
	complete, err := json.Marshal(map[string]any{"id": sub.id, "type": GraphqlWsComplete})
	if err != nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = h.adapter.SendMessage(ctx, string(complete))
}

func (h *GraphLinkSubscriptionHandler) remove(sub *glSubscription) {
	h.mu.Lock()
	delete(h.subs, sub.id)
	h.mu.Unlock()
	sub.finish()
}

func (h *GraphLinkSubscriptionHandler) onMessage(raw string) {
	var message glWsMessage
	if err := json.Unmarshal([]byte(raw), &message); err != nil {
		return
	}
	switch message.Type {
	case GraphqlWsConnectionAck:
		select {
		case h.ackCh <- struct{}{}:
		default:
		}
		return
	case GraphqlWsPing:
		pong, _ := json.Marshal(map[string]any{"type": GraphqlWsPong})
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = h.adapter.SendMessage(ctx, string(pong))
		return
	}
	h.mu.Lock()
	sub := h.subs[message.ID]
	h.mu.Unlock()
	if sub == nil {
		return
	}
	switch message.Type {
	case GraphqlWsNext:
		var payload struct {
			Data   json.RawMessage  `json:"data"`
			Errors []GraphLinkError `json:"errors"`
		}
		if err := json.Unmarshal(message.Payload, &payload); err != nil {
			sub.emit(GraphLinkRawEvent{Err: err})
			return
		}
		if glIsNull(payload.Data) && len(payload.Errors) > 0 {
			sub.emit(GraphLinkRawEvent{Err: &GraphLinkException{Errors: payload.Errors}})
			return
		}
		sub.emit(GraphLinkRawEvent{Data: payload.Data})
	case GraphqlWsComplete:
		h.remove(sub)
	case GraphqlWsError:
		var errs []GraphLinkError
		if err := json.Unmarshal(message.Payload, &errs); err != nil {
			errs = []GraphLinkError{{Message: string(message.Payload)}}
		}
		sub.emit(GraphLinkRawEvent{Err: &GraphLinkException{Errors: errs}})
		h.remove(sub)
	}
}

// glMapEvents decodes each raw subscription event into T on its own goroutine.
func glMapEvents[T any](raw <-chan GraphLinkRawEvent) <-chan GraphLinkEvent[T] {
	out := make(chan GraphLinkEvent[T], 64)
	go func() {
		defer close(out)
		for event := range raw {
			var item GraphLinkEvent[T]
			if event.Err != nil {
				item.Err = event.Err
			} else {
				item.Err = json.Unmarshal(event.Data, &item.Data)
			}
			out <- item
		}
	}()
	return out
}
''';

const goDefaultWebSocketAdapter = r'''
// DefaultGraphLinkWebSocketAdapter is a graphql-transport-ws client with automatic reconnect.
type DefaultGraphLinkWebSocketAdapter struct {
	URL             string
	HeadersProvider func(ctx context.Context) (map[string]string, error)
	Reconnect       bool
	Protocols       []string
	// MaxReconnectAttempts below zero retries forever.
	MaxReconnectAttempts int
	MaxReconnectDelay    time.Duration

	dialMu            sync.Mutex
	mu                sync.Mutex
	conn              *websocket.Conn
	readCancel        context.CancelFunc
	onMessage         func(string)
	onReconnect       func()
	reconnectListeners []func()
	reconnectAttempts int
	reconnecting      bool
	disposed          bool
}

func NewDefaultGraphLinkWebSocketAdapter(url string) *DefaultGraphLinkWebSocketAdapter {
	return &DefaultGraphLinkWebSocketAdapter{
		URL:                  url,
		Reconnect:            true,
		Protocols:            []string{"graphql-transport-ws"},
		MaxReconnectAttempts: 10,
		MaxReconnectDelay:    30 * time.Second,
	}
}

func (a *DefaultGraphLinkWebSocketAdapter) SetMessageHandler(handler func(message string)) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.onMessage = handler
}

func (a *DefaultGraphLinkWebSocketAdapter) SetReconnectHandler(handler func()) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.onReconnect = handler
}

// AddReconnectListener observes successful reconnects in addition to the subscription handler.
func (a *DefaultGraphLinkWebSocketAdapter) AddReconnectListener(listener func()) {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.reconnectListeners = append(a.reconnectListeners, listener)
}

func (a *DefaultGraphLinkWebSocketAdapter) ReconnectAttempts() int {
	a.mu.Lock()
	defer a.mu.Unlock()
	return a.reconnectAttempts
}

func (a *DefaultGraphLinkWebSocketAdapter) Connect(ctx context.Context) error {
	a.dialMu.Lock()
	defer a.dialMu.Unlock()
	a.mu.Lock()
	connected := a.conn != nil
	a.mu.Unlock()
	if connected {
		return nil
	}
	return a.dial(ctx)
}

func (a *DefaultGraphLinkWebSocketAdapter) dial(ctx context.Context) error {
	conn, _, err := websocket.Dial(ctx, a.URL, &websocket.DialOptions{Subprotocols: a.Protocols})
	if err != nil {
		a.mu.Lock()
		retry := a.Reconnect && !a.reconnecting && !a.disposed
		a.mu.Unlock()
		if retry {
			go a.reconnectLoop()
		}
		return err
	}
	conn.SetReadLimit(1 << 24)
	readCtx, cancel := context.WithCancel(context.Background())
	a.mu.Lock()
	a.conn = conn
	a.readCancel = cancel
	a.mu.Unlock()
	go a.readLoop(readCtx, conn)
	return nil
}

func (a *DefaultGraphLinkWebSocketAdapter) readLoop(ctx context.Context, conn *websocket.Conn) {
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			a.connectionClosed(conn, err)
			return
		}
		a.mu.Lock()
		handler := a.onMessage
		a.mu.Unlock()
		if handler != nil {
			handler(string(data))
		}
	}
}

func (a *DefaultGraphLinkWebSocketAdapter) connectionClosed(conn *websocket.Conn, err error) {
	a.mu.Lock()
	if a.conn != conn {
		a.mu.Unlock()
		return
	}
	a.conn = nil
	retry := a.Reconnect && !a.disposed && !a.reconnecting && websocket.CloseStatus(err) != websocket.StatusNormalClosure
	a.mu.Unlock()
	if retry {
		go a.reconnectLoop()
	}
}

func (a *DefaultGraphLinkWebSocketAdapter) reconnectLoop() {
	a.mu.Lock()
	if a.reconnecting {
		a.mu.Unlock()
		return
	}
	a.reconnecting = true
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		a.reconnecting = false
		a.mu.Unlock()
	}()
	for {
		a.mu.Lock()
		stop := a.disposed || (a.MaxReconnectAttempts >= 0 && a.reconnectAttempts >= a.MaxReconnectAttempts)
		attempt := a.reconnectAttempts
		if !stop {
			a.reconnectAttempts++
		}
		a.mu.Unlock()
		if stop {
			return
		}
		time.Sleep(a.backoff(attempt))
		a.mu.Lock()
		disposed := a.disposed
		a.mu.Unlock()
		if disposed {
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		err := a.Connect(ctx)
		cancel()
		if err != nil {
			continue
		}
		a.mu.Lock()
		a.reconnectAttempts = 0
		handler := a.onReconnect
		listeners := append([]func(){}, a.reconnectListeners...)
		a.mu.Unlock()
		if handler != nil {
			handler()
		}
		for _, listener := range listeners {
			listener()
		}
		return
	}
}

func (a *DefaultGraphLinkWebSocketAdapter) backoff(attempt int) time.Duration {
	delay := time.Second * time.Duration(math.Pow(2, float64(attempt)))
	if delay > a.MaxReconnectDelay || delay <= 0 {
		delay = a.MaxReconnectDelay
	}
	return delay + time.Duration(rand.Intn(1000))*time.Millisecond
}

func (a *DefaultGraphLinkWebSocketAdapter) SendMessage(ctx context.Context, message string) error {
	a.mu.Lock()
	conn := a.conn
	a.mu.Unlock()
	if conn == nil {
		return errors.New("WebSocket is not connected")
	}
	return conn.Write(ctx, websocket.MessageText, []byte(message))
}

func (a *DefaultGraphLinkWebSocketAdapter) ConnectionInitPayload(ctx context.Context) (map[string]any, error) {
	if a.HeadersProvider == nil {
		return nil, nil
	}
	headers, err := a.HeadersProvider(ctx)
	if err != nil || len(headers) == 0 {
		return nil, err
	}
	payload := make(map[string]any, len(headers))
	for key, value := range headers {
		payload[key] = value
	}
	return payload, nil
}

func (a *DefaultGraphLinkWebSocketAdapter) Close() error {
	a.mu.Lock()
	a.disposed = true
	a.reconnectAttempts = 0
	conn := a.conn
	cancel := a.readCancel
	a.conn = nil
	a.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if conn == nil {
		return nil
	}
	return conn.Close(websocket.StatusNormalClosure, "normal closure")
}
''';

String goHttpAdapter({
  required bool operationNameAsParameter,
  required bool useGet,
  required bool hasUploads,
}) {
  final opParam = operationNameAsParameter ? ', operationName string' : '';
  final postUrl = operationNameAsParameter ? 'a.URL + "?operationName=" + url.QueryEscape(operationName)' : 'a.URL';
  const base = r'''
// GraphLinkHttpAdapter sends GraphQL requests with net/http.
type GraphLinkHttpAdapter struct {
	URL             string
	HeadersProvider func(ctx context.Context) (map[string]string, error)
	Client          *http.Client
}

func NewGraphLinkHttpAdapter(url string) *GraphLinkHttpAdapter {
	return &GraphLinkHttpAdapter{URL: url, Client: http.DefaultClient}
}

func (a *GraphLinkHttpAdapter) do(ctx context.Context, request *http.Request) (*http.Response, error) {
	if a.HeadersProvider != nil {
		headers, err := a.HeadersProvider(ctx)
		if err != nil {
			return nil, err
		}
		for key, value := range headers {
			request.Header.Set(key, value)
		}
	}
	client := a.Client
	if client == nil {
		client = http.DefaultClient
	}
	return client.Do(request)
}

func glReadBody(response *http.Response) (string, error) {
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	return string(body), err
}

func (a *GraphLinkHttpAdapter) Call(ctx context.Context, payload string__OP_PARAM__) (string, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, __POST_URL__, strings.NewReader(payload))
	if err != nil {
		return "", err
	}
	request.Header.Set("Content-Type", "application/json")
	response, err := a.do(ctx, request)
	if err != nil {
		return "", err
	}
	return glReadBody(response)
}
''';
  const getCall = r'''

func (a *GraphLinkHttpAdapter) GetCall(ctx context.Context, payload string__OP_PARAM__) (string, error) {
	params, err := GraphLinkGetQueryParameters(payload)
	if err != nil {
		return "", err
	}
	target, err := url.Parse(a.URL)
	if err != nil {
		return "", err
	}
	query := target.Query()
	for key, values := range params {
		query[key] = values
	}
	target.RawQuery = query.Encode()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, target.String(), nil)
	if err != nil {
		return "", err
	}
	response, err := a.do(ctx, request)
	if err != nil {
		return "", err
	}
	if response.StatusCode == http.StatusMethodNotAllowed {
		response.Body.Close()
		return "", &GraphLinkGetNotSupported{Message: "GET is not allowed"}
	}
	return glReadBody(response)
}
''';
  const multipart = r'''

type glProgressReader struct {
	reader   io.Reader
	total    int64
	sent     int64
	callback UploadProgressCallback
}

func (p *glProgressReader) Read(buffer []byte) (int, error) {
	n, err := p.reader.Read(buffer)
	if n > 0 {
		p.sent += int64(n)
		p.callback(p.sent, p.total)
	}
	return n, err
}

// MultipartCall sends the GraphQL multipart request. The body is buffered so the
// total size is known for progress reporting.
func (a *GraphLinkHttpAdapter) MultipartCall(ctx context.Context, parts map[string]any, onProgress UploadProgressCallback) (string, error) {
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	keys := make([]string, 0, len(parts))
	for key := range parts {
		if key != "operations" && key != "map" {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	ordered := append([]string{"operations", "map"}, keys...)
	for _, key := range ordered {
		value, ok := parts[key]
		if !ok {
			continue
		}
		switch part := value.(type) {
		case string:
			if err := writer.WriteField(key, part); err != nil {
				return "", err
			}
		case GLUpload:
			header := make(textproto.MIMEHeader)
			header.Set("Content-Disposition", fmt.Sprintf(`form-data; name="%s"; filename="%s"`, key, part.Filename))
			header.Set("Content-Type", part.MimeType)
			field, err := writer.CreatePart(header)
			if err != nil {
				return "", err
			}
			_, err = io.Copy(field, part.Reader)
			if closer, ok := part.Reader.(io.Closer); ok {
				_ = closer.Close()
			}
			if err != nil {
				return "", err
			}
		default:
			return "", fmt.Errorf("unsupported multipart value for %q: %T", key, value)
		}
	}
	if err := writer.Close(); err != nil {
		return "", err
	}
	total := int64(body.Len())
	var reader io.Reader = bytes.NewReader(body.Bytes())
	if onProgress != nil {
		reader = &glProgressReader{reader: reader, total: total, callback: onProgress}
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, a.URL, reader)
	if err != nil {
		return "", err
	}
	request.ContentLength = total
	request.Header.Set("Content-Type", writer.FormDataContentType())
	response, err := a.do(ctx, request)
	if err != nil {
		return "", err
	}
	return glReadBody(response)
}
''';
  return [
    base.replaceAll('__OP_PARAM__', opParam).replaceAll('__POST_URL__', postUrl),
    if (useGet) getCall.replaceAll('__OP_PARAM__', opParam),
    if (hasUploads) multipart,
  ].join('\n');
}
