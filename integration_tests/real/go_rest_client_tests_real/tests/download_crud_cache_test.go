package tests

import (
	"context"
	"fmt"
	"io"
	"sync"
	"testing"
	"time"

	"graphlink.dev/resttests/generated"
)

func TestDownload(t *testing.T) {
	ctx, client := setup(t)
	d := must(client.Queries.Blob(ctx, 100000))
	eq(t, d.Filename, "blob-100000.bin")
	eq(t, d.Length, int64(100000))
	eq(t, string(d.ContentType[:24]), "application/octet-stream")
	eq(t, sha(must(d.Bytes())), sha(pattern(100000)))

	size := 8 * 1024 * 1024
	big := must(client.Queries.Blob(ctx, size))
	chunks, total := 0, 0
	buffer := make([]byte, 64*1024)
	for {
		n, err := big.Body.Read(buffer)
		total += n
		if n > 0 {
			chunks++
		}
		if err == io.EOF {
			break
		}
		mustOK(err)
	}
	big.Close()
	eq(t, total, size)
	isTrue(t, chunks > 1, "streamed in several chunks")

	var last [2]int64
	progress := must(client.Queries.Blob(ctx, 500000, generated.BlobOptions{OnReceiveProgress: func(r, tot int64) { last = [2]int64{r, tot} }}))
	must(progress.Bytes())
	eq(t, last, [2]int64{500000, 500000})

	eq(t, len(must(must(client.Queries.Blob(ctx, 0)).Bytes())), 0)

	_, err := client.Queries.Avatar(ctx, "p1")
	eq(t, restError(t, err).Status, 404)

	data := pattern(70000)
	mustOK(client.Mutations.UploadAvatar(ctx, "p1", upload(data, "", "image/png")))
	avatar := must(client.Queries.Avatar(ctx, "p1"))
	eq(t, avatar.Filename, "p1.png")
	eq(t, avatar.ContentType, "image/png")
	eq(t, must(avatar.Bytes()), data)
}

func TestNullableDownloadAndConcurrentDownloads(t *testing.T) {
	ctx, client := setup(t)
	none := must(client.Queries.AvatarOrEmpty(ctx, "p1"))
	isTrue(t, none == nil, "204 is nil when nullable")
	mustOK(client.Mutations.UploadAvatar(ctx, "p1", upload(pattern(10), "", "")))
	eq(t, must(must(client.Queries.AvatarOrEmpty(ctx, "p1")).Bytes()), pattern(10))

	var wg sync.WaitGroup
	lengths := make([]int, 5)
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			d, err := client.Queries.Blob(ctx, (i+1)*1000)
			if err != nil {
				return
			}
			data, _ := d.Bytes()
			lengths[i] = len(data)
		}(i)
	}
	wg.Wait()
	eq(t, lengths, []int{1000, 2000, 3000, 4000, 5000})
}

func TestCrudFlow(t *testing.T) {
	ctx, client := setup(t)
	created := must(client.Mutations.CreateProduct(ctx, generated.ProductIn{Name: "Lamp", Price: generated.Ptr(30.0), Tags: []string{"home"}}))
	eq(t, created.Name, "Lamp")
	eq(t, *created.Status, generated.StatusActive)
	eq(t, *must(client.Queries.Product(ctx, created.Id)).Price, 30.0)
	byTag := must(client.Queries.Products(ctx, generated.ProductsOptions{Filter: &generated.Filter{Tag: str("home")}}))
	eq(t, len(byTag), 1)
	eq(t, byTag[0].Id, created.Id)
	byIds := must(client.Queries.Products(ctx, generated.ProductsOptions{Ids: []string{"p1", created.Id}}))
	eq(t, len(byIds), 2)
	patched := must(client.Mutations.PatchProduct(ctx, created.Id, generated.ProductIn{Name: "Lamp 2", Price: generated.Ptr(35.0)}))
	eq(t, []any{patched.Name, *patched.Price}, []any{"Lamp 2", 35.0})
	renamed := must(client.Mutations.RenameProduct(ctx, created.Id, "Lamp 3", generated.RenameProductOptions{Note: str("n")}))
	eq(t, []any{renamed.Name, renamed.Tags}, []any{"Lamp 3", []string{"n"}})
	gallery := must(client.Mutations.Gallery(ctx, created.Id,
		[]generated.GLUpload{upload(pattern(100), "a.png", ""), upload(pattern(200), "b.png", "")},
		generated.GalleryOptions{Title: str("Gallery é")}))
	eq(t, []any{gallery.Name, gallery.Tags}, []any{"Gallery é", []string{"a.png", "b.png"}})
	eq(t, must(client.Mutations.ReplaceProduct(ctx, created.Id, generated.ProductIn{Name: "Final"})).Name, "Final")
	mustOK(client.Mutations.DeleteProduct(ctx, created.Id))
	_, err := client.Queries.Product(ctx, created.Id)
	eq(t, restError(t, err).Status, 404)
}

func TestVoidAndConcurrency(t *testing.T) {
	ctx, client := setup(t)
	mustOK(client.Mutations.DeleteProduct(ctx, "p2"))
	eq(t, restError(t, client.Mutations.DeleteProduct(ctx, "p2")).Status, 404)

	var wg sync.WaitGroup
	names, ids := sync.Map{}, sync.Map{}
	for i := 0; i < 40; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			p, err := client.Mutations.CreateProduct(ctx, generated.ProductIn{Name: fmt.Sprintf("item-%d", i)})
			if err == nil {
				names.Store(p.Name, true)
				ids.Store(p.Id, true)
			}
		}(i)
	}
	wg.Wait()
	count := func(m *sync.Map) int {
		n := 0
		m.Range(func(_, _ any) bool { n++; return true })
		return n
	}
	eq(t, []int{count(&names), count(&ids)}, []int{40, 40})
	eq(t, len(must(client.Queries.Products(ctx))), 41)

	results := make([]generated.Echo, 60)
	for i := 0; i < 60; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i], _ = client.Queries.EScalars(ctx, fmt.Sprintf("id%d", i), generated.EScalarsOptions{I: generated.Ptr(i)})
		}(i)
	}
	wg.Wait()
	for i, e := range results {
		eq(t, e.Path, fmt.Sprintf("/echo/scalars/id%d", i))
		v, _ := queryValue(e, "i")
		eq(t, v, fmt.Sprint(i))
	}
}

type countingStore struct {
	*generated.InMemoryGraphLinkCacheStore
	mu   sync.Mutex
	sets int
}

func (s *countingStore) Set(ctx context.Context, key, value string) error {
	s.mu.Lock()
	s.sets++
	s.mu.Unlock()
	return s.InMemoryGraphLinkCacheStore.Set(ctx, key, value)
}

func newCounting() *countingStore {
	return &countingStore{InMemoryGraphLinkCacheStore: generated.NewInMemoryGraphLinkCacheStore()}
}

func cacheSetup(t *testing.T) (context.Context, *generated.GraphLinkClient, *generated.InMemoryGraphLinkCacheStore) {
	ctx, _ := setup(t)
	store := generated.NewInMemoryGraphLinkCacheStore()
	return ctx, newClient(t, clientOptions{store: store}), store
}

func TestCacheQueries(t *testing.T) {
	ctx, client, store := cacheSetup(t)
	first := must(client.Queries.Counter(ctx, "a"))
	second := must(client.Queries.Counter(ctx, "a"))
	eq(t, []int{first.N, second.N}, []int{1, 1})
	eq(t, must(client.Queries.CounterUncached(ctx, "a")).N, 2)

	eq(t, must(client.Queries.Counter(ctx, "b")).N, 1)
	eq(t, must(client.Queries.Counter(ctx, "a")).N, 1)

	eq(t, must(client.Queries.CounterUncached(ctx, "u")).N, 1)
	eq(t, must(client.Queries.CounterUncached(ctx, "u")).N, 2)
	eq(t, must(client.Queries.CounterNoCache(ctx, "u")).N, 3)
	eq(t, must(client.Queries.CounterNoCache(ctx, "u")).N, 4)

	eq(t, must(client.Queries.CounterShort(ctx, "s")).N, 1)
	eq(t, must(client.Queries.CounterShort(ctx, "s")).N, 1)
	time.Sleep(1300 * time.Millisecond)
	eq(t, must(client.Queries.CounterShort(ctx, "s")).N, 2)

	_ = must(client.Queries.Counter(ctx, "shared"))
	eq(t, must(newClient(t, clientOptions{store: store}).Queries.Counter(ctx, "shared")).N, 1)
	eq(t, must(newClient(t).Queries.Counter(ctx, "shared")).N, 2)
}

func TestCacheInvalidation(t *testing.T) {
	ctx, client, _ := cacheSetup(t)
	eq(t, must(client.Queries.Counter(ctx, "c")).N, 1)
	must(client.Mutations.Bump(ctx, "c"))
	eq(t, must(client.Queries.Counter(ctx, "c")).N, 102)

	eq(t, must(client.Queries.CounterOther(ctx, "o")).N, 1)
	eq(t, must(client.Queries.Counter(ctx, "o")).N, 2)
	must(client.Mutations.Bump(ctx, "o"))
	eq(t, must(client.Queries.CounterOther(ctx, "o")).N, 1)
	isTrue(t, must(client.Queries.Counter(ctx, "o")).N > 100, "tagged entry was invalidated")

	_ = must(client.Queries.Counter(ctx, "x"))
	_ = must(client.Queries.CounterOther(ctx, "x"))
	must(client.Mutations.ResetAll(ctx, "x"))
	eq(t, must(client.Queries.Counter(ctx, "x")).N, 1)
	eq(t, must(client.Queries.CounterOther(ctx, "x")).N, 2)

	_ = must(client.Queries.Counter(ctx, "f"))
	_, err := client.Mutations.BumpFails(ctx, 500)
	restError(t, err)
	eq(t, must(client.Queries.Counter(ctx, "f")).N, 1)
	_, err = client.Mutations.BumpFails(ctx, 204)
	mustOK(err)
	eq(t, must(client.Queries.Counter(ctx, "f")).N, 2)
}

func TestCacheFailures(t *testing.T) {
	ctx, client, store := cacheSetup(t)
	writes := newCounting()
	counting := newClient(t, clientOptions{store: writes})
	_, err := counting.Queries.CachedStatus(ctx, 500)
	restError(t, err)
	eq(t, writes.sets, 0)
	eq(t, must(counting.Queries.CachedStatus(ctx, 200)).Id, "p1")
	eq(t, writes.sets, 1)

	bad := newCounting()
	badClient := newClient(t, clientOptions{store: bad})
	for i := 0; i < 2; i++ {
		_, err := badClient.Queries.CachedBad(ctx)
		isTrue(t, err != nil, "decode fails")
	}
	eq(t, bad.sets, 0)

	_ = must(client.Queries.CounterOffline(ctx, "off"))
	_ = must(client.Queries.CounterShort(ctx, "off2"))
	_ = must(client.Queries.Counter(ctx, "fresh"))
	time.Sleep(1300 * time.Millisecond)
	offline := newClient(t, clientOptions{base: deadURL, store: store})
	eq(t, must(offline.Queries.CounterOffline(ctx, "off")).N, 1)
	_, err = offline.Queries.CounterShort(ctx, "off2")
	notRest(t, err)
	_, err = offline.Queries.Counter(ctx, "never")
	notRest(t, err)
}

func TestFreshEntryServedWhenUnreachable(t *testing.T) {
	ctx, client, store := cacheSetup(t)
	_ = must(client.Queries.Counter(ctx, "fresh"))
	eq(t, must(newClient(t, clientOptions{base: deadURL, store: store}).Queries.Counter(ctx, "fresh")).N, 1)
}

func TestTransport(t *testing.T) {
	ctx, client := setup(t)
	for base, expected := range map[string]string{
		serverURL + "/api":  "/api/echo/scalars/p",
		serverURL + "/api/": "/api/echo/scalars/p",
		serverURL + "/":     "/echo/scalars/p",
	} {
		e := must(newClient(t, clientOptions{base: base}).Queries.EScalars(ctx, "p"))
		eq(t, e.Path, expected)
	}
	_, err := newClient(t, clientOptions{base: deadURL}).Queries.EAccept(ctx)
	notRest(t, err)
	eq(t, must(client.Queries.EAccept(ctx)).Method, "GET")
}
