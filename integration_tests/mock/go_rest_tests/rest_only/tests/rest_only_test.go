package tests

import (
	"context"
	"testing"

	"graphlink.dev/restmocks/generated"
)

func TestARestOnlySchemaNeedsNoGraphQLAdapter(t *testing.T) {
	client, err := generated.NewGraphLinkClient(generated.GraphLinkClientOptions{
		RestAdapter: func(ctx context.Context, request generated.RestRequest) (*generated.RestResponse, error) {
			return generated.NewRestResponse(200, []byte(`{"id":"p1","name":"Pen"}`), nil), nil
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	product, err := client.Queries.Product(context.Background(), "p1")
	if err != nil || product == nil || product.Name != "Pen" {
		t.Fatalf("unexpected result: %v %v", product, err)
	}
}
