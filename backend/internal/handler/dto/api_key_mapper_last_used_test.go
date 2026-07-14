package dto

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/service"
	"github.com/stretchr/testify/require"
)

func TestAPIKeyFromService_MapsLastUsedAt(t *testing.T) {
	lastUsed := time.Now().UTC().Truncate(time.Second)
	lastUsedIP := "203.0.113.10"
	src := &service.APIKey{
		ID:                 1,
		UserID:             2,
		Key:                "sk-map-last-used",
		Name:               "Mapper",
		Status:             service.StatusActive,
		LastUsedAt:         &lastUsed,
		LastUsedIP:         &lastUsedIP,
		CurrentConcurrency: 3,
	}

	out := APIKeyFromService(src)
	require.NotNil(t, out)
	require.NotNil(t, out.LastUsedAt)
	require.WithinDuration(t, lastUsed, *out.LastUsedAt, time.Second)
	require.NotNil(t, out.LastUsedIP)
	require.Equal(t, lastUsedIP, *out.LastUsedIP)
	require.Equal(t, 3, out.CurrentConcurrency)
}

func TestAPIKeyFromService_MapsNilLastUsedAt(t *testing.T) {
	src := &service.APIKey{
		ID:     1,
		UserID: 2,
		Key:    "sk-map-last-used-nil",
		Name:   "MapperNil",
		Status: service.StatusActive,
	}

	out := APIKeyFromService(src)
	require.NotNil(t, out)
	require.Nil(t, out.LastUsedAt)
	require.Nil(t, out.LastUsedIP)
}

func TestUserAPIKeyFromService_RedactsGroupRateMultipliers(t *testing.T) {
	src := &service.APIKey{
		ID:     1,
		UserID: 2,
		Key:    "sk-user-group-redacted",
		Name:   "MapperRedacted",
		Status: service.StatusActive,
		Group: &service.Group{
			ID:                  10,
			Name:                "standard",
			Description:         "Standard group",
			Platform:            "openai",
			RateMultiplier:      2.5,
			ImageRateMultiplier: 3.5,
			Status:              service.StatusActive,
		},
	}

	out := UserAPIKeyFromService(src)
	require.NotNil(t, out)
	require.NotNil(t, out.Group)
	require.Equal(t, int64(10), out.Group.ID)

	body, err := json.Marshal(out)
	require.NoError(t, err)
	require.NotContains(t, string(body), "rate_multiplier")
	require.NotContains(t, string(body), "image_rate_multiplier")
}
