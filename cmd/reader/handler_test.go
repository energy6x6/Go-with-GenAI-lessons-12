package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambdacontext"
)

func TestNormalizeHTTPInput(t *testing.T) {
	valid := `{"name":"  Олена   Коваль  ","email":" Reader@Example.COM "}`
	cases := []struct {
		name, body, method string
		encoded            bool
		want               int
	}{
		{"valid Unicode profile", valid, "POST", false, 200},
		{"base64 profile", base64.StdEncoding.EncodeToString([]byte(valid)), "POST", true, 200},
		{"malformed JSON", `{"name":`, "POST", false, 400},
		{"missing email", `{"name":"Олена"}`, "POST", false, 400},
		{"null object", `null`, "POST", false, 400},
		{"array", `[]`, "POST", false, 400},
		{"unknown field", `{"name":"A","email":"a@example.com","emali":"x"}`, "POST", false, 400},
		{"two objects", valid + valid, "POST", false, 400},
		{"trailing garbage", valid + `!`, "POST", false, 400},
		{"invalid base64", "!!!", "POST", true, 400},
		{"invalid UTF-8", "\xff", "POST", false, 400},
		{"oversized plain body", strings.Repeat("x", maxBodyBytes+1), "POST", false, 413},
		{"oversized encoded body", base64.StdEncoding.EncodeToString([]byte(strings.Repeat("x", maxBodyBytes+1))), "POST", true, 413},
		{"wrong HTTP method", valid, "GET", false, 405},
		{"display name email", `{"name":"A","email":"Reader <a@example.com>"}`, "POST", false, 400},
		{"overlong name", `{"name":"` + strings.Repeat("я", 121) + `","email":"a@example.com"}`, "POST", false, 400},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			req := events.APIGatewayProxyRequest{Body: tc.body, HTTPMethod: tc.method, IsBase64Encoded: tc.encoded}
			resp, err := handler(context.Background(), req)
			if err != nil || resp.StatusCode != tc.want {
				t.Fatalf("status=%d err=%v body=%s", resp.StatusCode, err, resp.Body)
			}
			if resp.Headers["Content-Type"] != "application/json" || !json.Valid([]byte(resp.Body)) {
				t.Fatalf("not a JSON response: %+v", resp)
			}
			if tc.want == 200 {
				var out struct {
					Status string `json:"status"`
					Reader Reader `json:"reader"`
				}
				if err := json.Unmarshal([]byte(resp.Body), &out); err != nil {
					t.Fatal(err)
				}
				if out.Status != "normalized" || out.Reader.Name != "Олена Коваль" || out.Reader.Email != "Reader@example.com" {
					t.Fatalf("unexpected output: %+v", out)
				}
			}
			if tc.want == 405 && resp.Headers["Allow"] != "POST" {
				t.Fatal("missing Allow header")
			}
		})
	}
}

func TestRequestIDAndMultipleValidationErrors(t *testing.T) {
	ctx := lambdacontext.NewContext(context.Background(), &lambdacontext.LambdaContext{AwsRequestID: "lambda-id"})
	req := events.APIGatewayProxyRequest{HTTPMethod: "POST", Body: `{}`}
	req.RequestContext.RequestID = "gateway-id"
	for _, tc := range []struct {
		ctx context.Context
		id  string
	}{{ctx, "lambda-id"}, {context.Background(), "gateway-id"}} {
		resp, err := handler(tc.ctx, req)
		if err != nil || resp.StatusCode != 400 || resp.Headers["X-Request-Id"] != tc.id {
			t.Fatalf("unexpected response: %+v, %v", resp, err)
		}
		var out struct {
			Details []string `json:"details"`
		}
		if err := json.Unmarshal([]byte(resp.Body), &out); err != nil {
			t.Fatal(err)
		}
		if len(out.Details) != 2 {
			t.Fatalf("want both validation errors, got %v", out.Details)
		}
	}
}

func TestReaderEventFixtures(t *testing.T) {
	for name, want := range map[string]int{"valid": 200, "invalid": 400, "malformed": 400} {
		t.Run(name, func(t *testing.T) {
			raw, err := os.ReadFile(filepath.Join("..", "..", "events", "reader", name+".json"))
			if err != nil {
				t.Fatal(err)
			}
			var req events.APIGatewayProxyRequest
			if err := json.Unmarshal(raw, &req); err != nil {
				t.Fatal(err)
			}
			resp, err := handler(context.Background(), req)
			if err != nil || resp.StatusCode != want {
				t.Fatalf("status=%d err=%v body=%s", resp.StatusCode, err, resp.Body)
			}
		})
	}
}
