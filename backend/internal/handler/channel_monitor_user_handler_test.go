//go:build unit

package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/Wei-Shaw/sub2api/internal/server/middleware"
	"github.com/Wei-Shaw/sub2api/internal/service"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

type fakeChannelMonitorUserService struct {
	views    []*service.UserMonitorView
	detail   *service.UserMonitorDetail
	listErr  error
	detailErr error
	detailID int64
}

func (f *fakeChannelMonitorUserService) ListUserView(context.Context) ([]*service.UserMonitorView, error) {
	return f.views, f.listErr
}

func (f *fakeChannelMonitorUserService) GetUserDetail(_ context.Context, id int64) (*service.UserMonitorDetail, error) {
	f.detailID = id
	return f.detail, f.detailErr
}

type fakeChannelMonitorGroupAccessService struct {
	groups []service.Group
	err    error
	calls  int
}

func (f *fakeChannelMonitorGroupAccessService) GetAvailableGroups(context.Context, int64) ([]service.Group, error) {
	f.calls++
	return f.groups, f.err
}

func TestChannelMonitorUserHandlerListFiltersToDefaultVisibleMonitor(t *testing.T) {
	gin.SetMode(gin.TestMode)

	monitorSvc := &fakeChannelMonitorUserService{
		views: []*service.UserMonitorView{
			{ID: 1, Name: "codelife-eu-monitor", GroupName: "codelife-openai"},
			{ID: 2, Name: "allgpt-monitor", GroupName: "codelife-openai"},
			{ID: 3, Name: "hidden", GroupName: "other-group"},
		},
	}
	groupSvc := &fakeChannelMonitorGroupAccessService{
		groups: []service.Group{{Name: "codelife-openai"}},
	}
	h := NewChannelMonitorUserHandler(monitorSvc, groupSvc, nil)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/api/v1/channel-monitors", nil)
	c.Set(string(middleware.ContextKeyUser), middleware.AuthSubject{UserID: 42})
	c.Set(string(middleware.ContextKeyUserRole), service.RoleUser)

	h.List(c)

	require.Equal(t, http.StatusOK, w.Code)
	require.Equal(t, 1, groupSvc.calls)

	var resp struct {
		Code int `json:"code"`
		Data struct {
			Items []channelMonitorUserListItem `json:"items"`
		} `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	require.Equal(t, 0, resp.Code)
	require.Len(t, resp.Data.Items, 1)
	require.Equal(t, "codelife-openai", resp.Data.Items[0].GroupName)
	require.Equal(t, "codelife-eu-monitor", resp.Data.Items[0].Name)
}

func TestChannelMonitorUserHandlerListAdminBypassesGroupFilter(t *testing.T) {
	gin.SetMode(gin.TestMode)

	monitorSvc := &fakeChannelMonitorUserService{
		views: []*service.UserMonitorView{
			{ID: 1, Name: "codelife-eu-monitor", GroupName: "codelife-openai"},
			{ID: 2, Name: "allgpt-monitor", GroupName: "codelife-openai"},
		},
	}
	groupSvc := &fakeChannelMonitorGroupAccessService{
		groups: []service.Group{{Name: "codelife-openai"}},
	}
	h := NewChannelMonitorUserHandler(monitorSvc, groupSvc, nil)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/api/v1/channel-monitors", nil)
	c.Set(string(middleware.ContextKeyUser), middleware.AuthSubject{UserID: 1})
	c.Set(string(middleware.ContextKeyUserRole), service.RoleAdmin)

	h.List(c)

	require.Equal(t, http.StatusOK, w.Code)
	require.Equal(t, 0, groupSvc.calls)

	var resp struct {
		Data struct {
			Items []channelMonitorUserListItem `json:"items"`
		} `json:"data"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	require.Len(t, resp.Data.Items, 2)
}

func TestChannelMonitorUserHandlerGetStatusReturns404ForHiddenMonitorName(t *testing.T) {
	gin.SetMode(gin.TestMode)

	monitorSvc := &fakeChannelMonitorUserService{
		detail: &service.UserMonitorDetail{
			ID:        9,
			Name:      "allgpt-monitor",
			GroupName: "codelife-openai",
		},
	}
	groupSvc := &fakeChannelMonitorGroupAccessService{
		groups: []service.Group{{Name: "codelife-openai"}},
	}
	h := NewChannelMonitorUserHandler(monitorSvc, groupSvc, nil)

	w := httptest.NewRecorder()
	c, _ := gin.CreateTestContext(w)
	c.Request = httptest.NewRequest(http.MethodGet, "/api/v1/channel-monitors/9/status", nil)
	c.Params = gin.Params{{Key: "id", Value: "9"}}
	c.Set(string(middleware.ContextKeyUser), middleware.AuthSubject{UserID: 7})
	c.Set(string(middleware.ContextKeyUserRole), service.RoleUser)

	h.GetStatus(c)

	require.Equal(t, int64(9), monitorSvc.detailID)
	require.Equal(t, http.StatusNotFound, w.Code)

	var resp struct {
		Reason string `json:"reason"`
	}
	require.NoError(t, json.Unmarshal(w.Body.Bytes(), &resp))
	require.Equal(t, "CHANNEL_MONITOR_NOT_FOUND", resp.Reason)
}
