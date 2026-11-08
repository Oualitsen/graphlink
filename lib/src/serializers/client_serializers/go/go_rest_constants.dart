const goRestFile = r'''
type DownloadProgressCallback func(received, total int64)

type GLRestAdapter func(ctx context.Context, request RestRequest) (*RestResponse, error)

type RestEntry struct {
	Name  string
	Value string
}

type RestPart struct {
	Name     string
	Value    string
	File     *GLUpload
	MimeType string
}

type RestBody interface{ isRestBody() }

type RestJSONBody struct{ JSON []byte }

type RestFormBody struct{ Fields []RestEntry }

type RestMultipartBody struct{ Parts []RestPart }

type RestRawBody struct{ Upload GLUpload }

func (RestJSONBody) isRestBody()      {}
func (RestFormBody) isRestBody()      {}
func (RestMultipartBody) isRestBody() {}
func (RestRawBody) isRestBody()       {}

type RestRequest struct {
	Method         string
	Path           string
	Query          []RestEntry
	Headers        map[string]string
	Body           RestBody
	OnSendProgress UploadProgressCallback
}

// RestResponse carries lower-cased header names; Body must be read or closed.
type RestResponse struct {
	Status  int
	Headers map[string]string
	Body    io.ReadCloser
}

func NewRestResponse(status int, body []byte, headers map[string]string) *RestResponse {
	if headers == nil {
		headers = map[string]string{}
	}
	return &RestResponse{Status: status, Headers: headers, Body: io.NopCloser(bytes.NewReader(body))}
}

func (r *RestResponse) IsSuccess() bool { return r.Status >= 200 && r.Status < 300 }

func (r *RestResponse) Bytes() ([]byte, error) {
	defer r.Body.Close()
	data, err := io.ReadAll(r.Body)
	return bytes.TrimPrefix(data, []byte("\xef\xbb\xbf")), err
}

func (r *RestResponse) Text() (string, error) {
	data, err := r.Bytes()
	return string(data), err
}

func (r *RestResponse) Drain() error {
	defer r.Body.Close()
	_, err := io.Copy(io.Discard, r.Body)
	return err
}

type RestError struct {
	Status  int
	Headers map[string]string
	Body    string
}

func (e *RestError) Error() string { return fmt.Sprintf("RestError(%d): %s", e.Status, e.Body) }

type GLDownload struct {
	Body        io.ReadCloser
	Filename    string
	ContentType string
	// Length is -1 when the server did not announce it.
	Length int64
}

func (d *GLDownload) Bytes() ([]byte, error) {
	defer d.Body.Close()
	return io.ReadAll(d.Body)
}

func (d *GLDownload) Close() error { return d.Body.Close() }

type restProgressReader struct {
	reader io.ReadCloser
	count  int64
	total  int64
	notify func(count, total int64)
}

func (p *restProgressReader) Read(buffer []byte) (int, error) {
	n, err := p.reader.Read(buffer)
	if n > 0 {
		p.count += int64(n)
		p.notify(p.count, p.total)
	}
	return n, err
}

func (p *restProgressReader) Close() error { return p.reader.Close() }

var restFilenamePattern = regexp.MustCompile(`(?i)filename\*?=(?:UTF-8'')?"?([^";]+)"?`)

func restNewDownload(response *RestResponse, onProgress DownloadProgressCallback) *GLDownload {
	length := int64(-1)
	if value, ok := response.Headers["content-length"]; ok {
		if parsed, err := strconv.ParseInt(value, 10, 64); err == nil {
			length = parsed
		}
	}
	var body io.ReadCloser = response.Body
	if onProgress != nil {
		body = &restProgressReader{reader: response.Body, total: length, notify: onProgress}
	}
	filename := ""
	if match := restFilenamePattern.FindStringSubmatch(response.Headers["content-disposition"]); match != nil {
		filename = match[1]
		if decoded, err := url.PathUnescape(match[1]); err == nil {
			filename = decoded
		}
	}
	return &GLDownload{Body: body, Filename: filename, ContentType: response.Headers["content-type"], Length: length}
}

func restEncode(value string) string {
	var builder strings.Builder
	for _, c := range []byte(value) {
		if c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '_' || c == '.' || c == '~' {
			builder.WriteByte(c)
		} else {
			fmt.Fprintf(&builder, "%%%02X", c)
		}
	}
	return builder.String()
}

func restEncodeQuery(value string) string { return strings.ReplaceAll(restEncode(value), "%20", "+") }

func restPath(value any) string { return restEncode(restScalarText(restNormalize(value))) }

func restURL(baseURL string, request RestRequest) string {
	base := strings.TrimSuffix(baseURL, "/")
	pairs := make([]string, len(request.Query))
	for i, entry := range request.Query {
		pairs[i] = restEncodeQuery(entry.Name) + "=" + restEncodeQuery(entry.Value)
	}
	if len(pairs) == 0 {
		return base + request.Path
	}
	return base + request.Path + "?" + strings.Join(pairs, "&")
}

func restFormBody(fields []RestEntry) string {
	pairs := make([]string, len(fields))
	for i, entry := range fields {
		pairs[i] = restEncodeQuery(entry.Name) + "=" + restEncodeQuery(entry.Value)
	}
	return strings.Join(pairs, "&")
}

type restObject struct {
	keys   []string
	values map[string]any
}

func restParseValue(decoder *json.Decoder) (any, error) {
	token, err := decoder.Token()
	if err != nil {
		return nil, err
	}
	delim, ok := token.(json.Delim)
	if !ok {
		return token, nil
	}
	if delim == '{' {
		object := &restObject{values: map[string]any{}}
		for decoder.More() {
			keyToken, err := decoder.Token()
			if err != nil {
				return nil, err
			}
			key := keyToken.(string)
			value, err := restParseValue(decoder)
			if err != nil {
				return nil, err
			}
			object.keys = append(object.keys, key)
			object.values[key] = value
		}
		_, err := decoder.Token()
		return object, err
	}
	list := []any{}
	for decoder.More() {
		value, err := restParseValue(decoder)
		if err != nil {
			return nil, err
		}
		list = append(list, value)
	}
	_, err = decoder.Token()
	return list, err
}

// restNormalize turns any Go value into an ordered JSON tree: nil, string, bool, json.Number, []any or *restObject.
func restNormalize(value any) any {
	encoded, err := json.Marshal(value)
	if err != nil {
		return nil
	}
	decoder := json.NewDecoder(bytes.NewReader(encoded))
	decoder.UseNumber()
	parsed, err := restParseValue(decoder)
	if err != nil {
		return nil
	}
	return parsed
}

func restScalarText(value any) string {
	switch v := value.(type) {
	case nil:
		return ""
	case string:
		return v
	case bool:
		return strconv.FormatBool(v)
	case json.Number:
		return v.String()
	default:
		return fmt.Sprint(v)
	}
}

func restJoinKey(key, name string, bracket bool) string {
	if bracket {
		return key + "[" + name + "]"
	}
	return key + "." + name
}

func restCollect(out *[]RestEntry, key string, value any, bracket, comma, inList bool) {
	switch v := value.(type) {
	case nil:
		return
	case []any:
		items := make([]any, 0, len(v))
		scalar := true
		for _, item := range v {
			if item == nil {
				continue
			}
			items = append(items, item)
			switch item.(type) {
			case []any, *restObject:
				scalar = false
			}
		}
		if len(items) == 0 {
			return
		}
		if !inList && scalar {
			if comma {
				texts := make([]string, len(items))
				for i, item := range items {
					texts[i] = restScalarText(item)
				}
				*out = append(*out, RestEntry{key, strings.Join(texts, ",")})
			} else {
				for _, item := range items {
					*out = append(*out, RestEntry{key, restScalarText(item)})
				}
			}
			return
		}
		for i, item := range v {
			restCollect(out, restJoinKey(key, strconv.Itoa(i), bracket), item, bracket, comma, true)
		}
	case *restObject:
		for _, name := range v.keys {
			restCollect(out, restJoinKey(key, name, bracket), v.values[name], bracket, comma, false)
		}
	default:
		*out = append(*out, RestEntry{key, restScalarText(v)})
	}
}

func restEntries(key string, value any, bracket, comma bool) []RestEntry {
	out := []RestEntry{}
	restCollect(&out, key, restNormalize(value), bracket, comma, false)
	return out
}

func restSpreadEntries(value any, names [][2]string, bracket, comma bool) []RestEntry {
	out := []RestEntry{}
	if object, ok := restNormalize(value).(*restObject); ok {
		for _, name := range names {
			restCollect(&out, name[1], object.values[name[0]], bracket, comma, false)
		}
	}
	return out
}

func restHeaderValue(value any) string {
	if list, ok := value.([]any); ok {
		texts := make([]string, 0, len(list))
		for _, item := range list {
			if item != nil {
				texts = append(texts, restScalarText(item))
			}
		}
		return strings.Join(texts, ",")
	}
	return restScalarText(value)
}

func restHeader(name string, value any) map[string]string {
	normalized := restNormalize(value)
	if normalized == nil {
		return map[string]string{}
	}
	return map[string]string{name: restHeaderValue(normalized)}
}

func restHeaders(value any, names [][2]string) map[string]string {
	out := map[string]string{}
	if object, ok := restNormalize(value).(*restObject); ok {
		for _, name := range names {
			if field := object.values[name[0]]; field != nil {
				out[name[1]] = restHeaderValue(field)
			}
		}
	}
	return out
}

func restHeaderSet(maps ...map[string]string) map[string]string {
	out := map[string]string{}
	for _, m := range maps {
		for key, value := range m {
			out[key] = value
		}
	}
	return out
}

func restContentType(present bool, value string) map[string]string {
	if !present {
		return map[string]string{}
	}
	return map[string]string{"Content-Type": value}
}

func restRawContentType(body RestBody) map[string]string {
	if raw, ok := body.(RestRawBody); ok {
		return map[string]string{"Content-Type": raw.Upload.MimeType}
	}
	return map[string]string{}
}

func restConcat[T any](lists ...[]T) []T {
	out := []T{}
	for _, list := range lists {
		out = append(out, list...)
	}
	return out
}

func restTextParts(entries []RestEntry) []RestPart {
	parts := make([]RestPart, len(entries))
	for i, entry := range entries {
		parts[i] = RestPart{Name: entry.Name, Value: entry.Value}
	}
	return parts
}

func restFilePart(name string, upload *GLUpload) []RestPart {
	if upload == nil {
		return []RestPart{}
	}
	return []RestPart{{Name: name, File: upload}}
}

func restFileParts(name string, uploads []GLUpload) []RestPart {
	parts := make([]RestPart, len(uploads))
	for i := range uploads {
		parts[i] = RestPart{Name: name, File: &uploads[i]}
	}
	return parts
}

func restJSONPart(name string, value any) []RestPart {
	if restNormalize(value) == nil {
		return []RestPart{}
	}
	return []RestPart{{Name: name, Value: restJSONString(value), MimeType: "application/json"}}
}

func restJSONEntry(name string, value any) []RestEntry {
	if restNormalize(value) == nil {
		return []RestEntry{}
	}
	return []RestEntry{{Name: name, Value: restJSONString(value)}}
}

func restJSONString(value any) string {
	encoded, err := json.Marshal(value)
	if err != nil {
		return "null"
	}
	return string(encoded)
}

func restNavigate(raw json.RawMessage, path []string) (json.RawMessage, error) {
	current := raw
	for _, segment := range path {
		if glIsNull(current) {
			return nil, nil
		}
		var object map[string]json.RawMessage
		if err := json.Unmarshal(current, &object); err != nil {
			return nil, nil
		}
		current = object[segment]
	}
	return current, nil
}

func restDecode[T any](raw json.RawMessage) (T, error) {
	var value T
	if glIsNull(raw) {
		return value, nil
	}
	err := json.Unmarshal(raw, &value)
	return value, err
}

func glProbeString(raw json.RawMessage) string {
	var text string
	if json.Unmarshal(raw, &text) == nil {
		return text
	}
	return strings.Trim(string(raw), `"`)
}
''';

String goRestNoGraphQL(bool withOperationName) => '''
func glNoGraphQL__(ctx context.Context, payload string${withOperationName ? ', operationName string' : ''}) (string, error) {
	return "", errors.New("This schema has no GraphQL operation: pass no GraphQL adapter")
}
''';

const goRestResolver = r'''
type GraphLinkRestResolver struct {
	GraphLinkResolverBase
	restAdapter GLRestAdapter
}

func (r *GraphLinkRestResolver) restCall(ctx context.Context, request RestRequest) (*RestResponse, error) {
	if r.restAdapter == nil {
		return nil, errors.New("no REST adapter configured")
	}
	response, err := r.restAdapter(ctx, request)
	if err != nil {
		return nil, err
	}
	if !response.IsSuccess() {
		body, readErr := response.Text()
		if readErr != nil {
			return nil, readErr
		}
		return nil, &RestError{Status: response.Status, Headers: response.Headers, Body: body}
	}
	return response, nil
}

func (r *GraphLinkRestResolver) restVoid(ctx context.Context, request RestRequest) error {
	response, err := r.restCall(ctx, request)
	if err != nil {
		return err
	}
	return response.Drain()
}

func (r *GraphLinkRestResolver) restDownload(ctx context.Context, request RestRequest, allowEmpty bool, onProgress DownloadProgressCallback) (*GLDownload, error) {
	response, err := r.restCall(ctx, request)
	if err != nil {
		return nil, err
	}
	if response.Status == 204 {
		if err := response.Drain(); err != nil {
			return nil, err
		}
		if allowEmpty {
			return nil, nil
		}
		return nil, fmt.Errorf("Empty REST response for a non-null download of %s %s", request.Method, request.Path)
	}
	return restNewDownload(response, onProgress), nil
}

func (r *GraphLinkRestResolver) restTextBody(ctx context.Context, request RestRequest) (string, error) {
	response, err := r.restCall(ctx, request)
	if err != nil {
		return "", err
	}
	return response.Text()
}

func (r *GraphLinkRestResolver) restTextOrNil(ctx context.Context, request RestRequest) (*string, error) {
	text, err := r.restTextBody(ctx, request)
	if err != nil || text == "" {
		return nil, err
	}
	return &text, nil
}

func (r *GraphLinkRestResolver) restJSON(ctx context.Context, request RestRequest, path []string, allowEmpty bool) (json.RawMessage, error) {
	response, err := r.restCall(ctx, request)
	if err != nil {
		return nil, err
	}
	data, err := response.Bytes()
	if err != nil {
		return nil, err
	}
	raw := json.RawMessage(data)
	if !glIsNull(raw) {
		if raw, err = restNavigate(raw, path); err != nil {
			return nil, err
		}
	}
	if glIsNull(raw) {
		if !allowEmpty {
			return nil, fmt.Errorf("Empty REST response for a non-null result of %s %s", request.Method, request.Path)
		}
		return nil, nil
	}
	return raw, nil
}

func restCached[T any](
	ctx context.Context,
	r *GraphLinkRestResolver,
	name string,
	variables map[string]any,
	ttl int,
	tags []string,
	staleIfOffline bool,
	fetch func() (json.RawMessage, error),
	decode func(json.RawMessage) (T, error),
) (T, error) {
	var zero T
	key := ComputeGraphLinkCacheKey(name, variables)
	cached, _ := r.getFromCache(ctx, key, tags, staleIfOffline)
	if cached != nil && !cached.Stale {
		return decode(json.RawMessage(cached.Data))
	}
	raw, err := fetch()
	if err != nil {
		var restErr *RestError
		if errors.As(err, &restErr) {
			return zero, err
		}
		if cached != nil {
			return decode(json.RawMessage(cached.Data))
		}
		return zero, err
	}
	value, err := decode(raw)
	if err != nil {
		return zero, err
	}
	if !glIsNull(raw) {
		encoded, err := NewGraphLinkCacheEntry(string(raw), time.Now().UnixMilli()+int64(ttl)*1000).Encode()
		if err != nil {
			return zero, err
		}
		if err := r.store.Set(ctx, key, encoded); err != nil {
			return zero, err
		}
		if len(tags) > 0 {
			if err := r.addKeyToTags(ctx, key, tags); err != nil {
				return zero, err
			}
		}
	}
	return value, nil
}
''';

const goRestHttpAdapter = r'''
// GraphLinkRestHttpAdapter sends REST operations with net/http.
type GraphLinkRestHttpAdapter struct {
	BaseURL         string
	HeadersProvider func(ctx context.Context) (map[string]string, error)
	Client          *http.Client
}

func NewGraphLinkRestHttpAdapter(baseURL string) *GraphLinkRestHttpAdapter {
	return &GraphLinkRestHttpAdapter{BaseURL: baseURL, Client: http.DefaultClient}
}

func (a *GraphLinkRestHttpAdapter) Call(ctx context.Context, request RestRequest) (*RestResponse, error) {
	headers := map[string]string{}
	if a.HeadersProvider != nil {
		provided, err := a.HeadersProvider(ctx)
		if err != nil {
			return nil, err
		}
		for key, value := range provided {
			headers[key] = value
		}
	}
	for key, value := range request.Headers {
		headers[key] = value
	}

	var body io.Reader
	contentLength := int64(0)
	switch b := request.Body.(type) {
	case RestJSONBody:
		body, contentLength = bytes.NewReader(b.JSON), int64(len(b.JSON))
	case RestFormBody:
		encoded := restFormBody(b.Fields)
		body, contentLength = strings.NewReader(encoded), int64(len(encoded))
	case RestMultipartBody:
		streamParts := make([]glMultipartPart, len(b.Parts))
		for i, part := range b.Parts {
			streamParts[i] = glMultipartPart(part)
		}
		contentType, stream, length, closeAll := glMultipartStream(streamParts)
		defer closeAll()
		headers["Content-Type"] = contentType
		body, contentLength = restUploadReader(stream, length, request.OnSendProgress), length
	case RestRawBody:
		body, contentLength = restUploadReader(b.Upload.Reader, b.Upload.Length, request.OnSendProgress), b.Upload.Length
	}

	httpRequest, err := http.NewRequestWithContext(ctx, request.Method, restURL(a.BaseURL, request), body)
	if err != nil {
		return nil, err
	}
	if body != nil {
		httpRequest.ContentLength = contentLength
		if contentLength == 0 {
			httpRequest.Body = http.NoBody
		}
	}
	for key, value := range headers {
		httpRequest.Header.Set(key, value)
	}
	client := a.Client
	if client == nil {
		client = http.DefaultClient
	}
	httpResponse, err := client.Do(httpRequest)
	if err != nil {
		return nil, err
	}
	responseHeaders := map[string]string{}
	for key, values := range httpResponse.Header {
		responseHeaders[strings.ToLower(key)] = strings.Join(values, ", ")
	}
	return &RestResponse{Status: httpResponse.StatusCode, Headers: responseHeaders, Body: httpResponse.Body}, nil
}

func restUploadReader(reader io.Reader, total int64, onProgress UploadProgressCallback) io.Reader {
	if reader == nil {
		return bytes.NewReader(nil)
	}
	if onProgress == nil || total <= 0 {
		return reader
	}
	return &restSendReader{reader: reader, total: total, notify: onProgress}
}

type restSendReader struct {
	reader io.Reader
	count  int64
	total  int64
	notify UploadProgressCallback
}

func (p *restSendReader) Read(buffer []byte) (int, error) {
	n, err := p.reader.Read(buffer)
	if n > 0 {
		p.count += int64(n)
		p.notify(p.count, p.total)
	}
	return n, err
}

func (p *restSendReader) Close() error {
	if closer, ok := p.reader.(io.Closer); ok {
		return closer.Close()
	}
	return nil
}
''';
