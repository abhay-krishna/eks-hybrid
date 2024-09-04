package iamrolesanywhere

import (
	"context"
	"fmt"
	"net/http"
	"runtime"
	"time"

	"github.com/aws/eks-hybrid/internal/artifact"
)

const signingHelperVersion = "1.2.0"

type signingHelperSource struct {
	client http.Client
}

// SigningHelper provides a SigningHelper that retrieves the binary from an official release
// channels.
func NewSigningHelper() SigningHelperSource {
	return signingHelperSource{
		client: http.Client{Timeout: 120 * time.Second},
	}
}

// GetSigningHelper retrieves the aws_sigining_helper for IAM Roles Anywhere.
func (src signingHelperSource) GetSigningHelper(ctx context.Context) (artifact.Source, error) {
	if runtime.GOARCH != "amd64" {
		return nil, fmt.Errorf("signing helper: unsupported architecture: %v", runtime.GOARCH)
	}

	url := fmt.Sprintf("https://rolesanywhere.amazonaws.com/releases/%v/X86_64/Linux/aws_signing_helper", signingHelperVersion)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}

	resp, err := src.client.Do(req)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("non-200 status code: %v", resp.StatusCode)
	}

	return artifact.WithNopChecksum(resp.Body), nil
}
