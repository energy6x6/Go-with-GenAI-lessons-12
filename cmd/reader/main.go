package main

import (
	"log/slog"
	"os"

	"github.com/aws/aws-lambda-go/lambda"
)

var logger = slog.New(slog.NewJSONHandler(os.Stdout, nil))

func main() {
	lambda.Start(handler)
}
