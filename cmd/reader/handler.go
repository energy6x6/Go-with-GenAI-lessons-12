package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/mail"
	"strings"
	"unicode/utf8"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambdacontext"
)

const maxBodyBytes = 64 * 1024

type Reader struct {
	Name  string `json:"name"`
	Email string `json:"email"`
}

// handler normalizes a reader profile without storing personal data.
// Expected input errors are HTTP responses with a nil invocation error.
func handler(ctx context.Context, req events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	id := req.RequestContext.RequestID
	if lc, ok := lambdacontext.FromContext(ctx); ok && lc.AwsRequestID != "" {
		id = lc.AwsRequestID
	}
	if id == "" {
		id = "local"
	}
	if req.HTTPMethod != "POST" {
		resp := respond(id, 405, map[string]any{"error": "method must be POST"})
		resp.Headers["Allow"] = "POST"
		return resp, nil
	}

	// Reject oversized input before allocating space for base64 decoding.
	if len(req.Body) > base64.StdEncoding.EncodedLen(maxBodyBytes) {
		return respond(id, 413, map[string]any{"error": "body exceeds 64 KiB"}), nil
	}
	body := []byte(req.Body)
	if req.IsBase64Encoded {
		var err error
		body, err = base64.StdEncoding.DecodeString(req.Body)
		if err != nil {
			return respond(id, 400, map[string]any{"error": "invalid base64 body"}), nil
		}
	}
	if len(body) > maxBodyBytes {
		return respond(id, 413, map[string]any{"error": "body exceeds 64 KiB"}), nil
	}
	if !utf8.Valid(body) {
		return respond(id, 400, map[string]any{"error": "body must be UTF-8"}), nil
	}

	var in *Reader
	dec := json.NewDecoder(strings.NewReader(string(body)))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&in); err != nil || in == nil {
		return respond(id, 400, map[string]any{"error": "expected an object with name and email"}), nil
	}
	if err := dec.Decode(new(any)); err != io.EOF {
		return respond(id, 400, map[string]any{"error": "expected exactly one JSON object"}), nil
	}

	out, problems := normalize(*in)
	if len(problems) > 0 {
		logger.WarnContext(ctx, "reader validation failed", "request_id", id, "problem_count", len(problems))
		return respond(id, 400, map[string]any{"error": "validation failed", "details": problems}), nil
	}
	logger.InfoContext(ctx, "reader normalized", "request_id", id)
	return respond(id, 200, map[string]any{"status": "normalized", "reader": out}), nil
}

func normalize(in Reader) (Reader, []string) {
	out := Reader{Name: strings.Join(strings.Fields(in.Name), " "), Email: strings.TrimSpace(in.Email)}
	var problems []string
	if n := utf8.RuneCountInString(out.Name); n == 0 || n > 120 {
		problems = append(problems, "name must contain 1 to 120 characters")
	}
	addr, err := mail.ParseAddress(out.Email)
	if err != nil || addr.Address != out.Email || addr.Name != "" {
		problems = append(problems, "email must be a single email address without a display name")
	} else {
		// Preserve the potentially case-sensitive local part, normalize only the domain.
		at := strings.LastIndexByte(out.Email, '@')
		out.Email = out.Email[:at+1] + strings.ToLower(out.Email[at+1:])
	}
	return out, problems
}

func respond(id string, status int, body any) events.APIGatewayProxyResponse {
	raw, _ := json.Marshal(body) // Only JSON-compatible types are passed by this package.
	return events.APIGatewayProxyResponse{
		StatusCode: status,
		Headers:    map[string]string{"Content-Type": "application/json", "X-Request-Id": id},
		Body:       string(raw),
	}
}
