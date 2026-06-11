package handler

import (
	"context"
	"strings"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/handler/admin"
	"github.com/Wei-Shaw/sub2api/internal/handler/dto"
	"github.com/Wei-Shaw/sub2api/internal/pkg/response"
	"github.com/Wei-Shaw/sub2api/internal/server/middleware"
	"github.com/Wei-Shaw/sub2api/internal/service"

	"github.com/gin-gonic/gin"
)

const defaultUserVisibleMonitorName = "codelife-eu-monitor"

type channelMonitorUserService interface {
	ListUserView(ctx context.Context) ([]*service.UserMonitorView, error)
	GetUserDetail(ctx context.Context, id int64) (*service.UserMonitorDetail, error)
}

type channelMonitorGroupAccessService interface {
	GetAvailableGroups(ctx context.Context, userID int64) ([]service.Group, error)
}

// ChannelMonitorUserHandler 渠道监控用户只读 handler。
type ChannelMonitorUserHandler struct {
	monitorService channelMonitorUserService
	groupService   channelMonitorGroupAccessService
	settingService *service.SettingService
}

// NewChannelMonitorUserHandler 创建 handler。
// settingService 用于每次请求前读取功能开关；关闭时 List/GetStatus 直接返回空/404。
func NewChannelMonitorUserHandler(
	monitorService channelMonitorUserService,
	groupService channelMonitorGroupAccessService,
	settingService *service.SettingService,
) *ChannelMonitorUserHandler {
	return &ChannelMonitorUserHandler{
		monitorService: monitorService,
		groupService:   groupService,
		settingService: settingService,
	}
}

// featureEnabled 返回当前渠道监控功能是否开启。
// settingService 为 nil（测试场景）视为启用。
func (h *ChannelMonitorUserHandler) featureEnabled(c *gin.Context) bool {
	if h.settingService == nil {
		return true
	}
	return h.settingService.GetChannelMonitorRuntime(c.Request.Context()).Enabled
}

func (h *ChannelMonitorUserHandler) isAdmin(c *gin.Context) bool {
	role, ok := middleware.GetUserRoleFromContext(c)
	return ok && role == service.RoleAdmin
}

func (h *ChannelMonitorUserHandler) visibleGroupNames(c *gin.Context) (map[string]struct{}, bool) {
	subject, ok := middleware.GetAuthSubjectFromContext(c)
	if !ok {
		response.Unauthorized(c, "User not authenticated")
		return nil, false
	}
	if h.groupService == nil {
		response.InternalError(c, "Channel monitor group filter unavailable")
		return nil, false
	}
	groups, err := h.groupService.GetAvailableGroups(c.Request.Context(), subject.UserID)
	if err != nil {
		response.ErrorFrom(c, err)
		return nil, false
	}
	return buildAllowedGroupNameSet(groups), true
}

func buildAllowedGroupNameSet(groups []service.Group) map[string]struct{} {
	out := make(map[string]struct{}, len(groups))
	for _, group := range groups {
		name := strings.TrimSpace(group.Name)
		if name == "" {
			continue
		}
		out[name] = struct{}{}
	}
	return out
}

func canViewMonitorGroup(groupName string, allowed map[string]struct{}) bool {
	if len(allowed) == 0 {
		return false
	}
	_, ok := allowed[strings.TrimSpace(groupName)]
	return ok
}

func canViewMonitorName(name string) bool {
	return strings.EqualFold(strings.TrimSpace(name), defaultUserVisibleMonitorName)
}

func filterUserMonitorViewsByGroup(
	views []*service.UserMonitorView,
	allowed map[string]struct{},
) []*service.UserMonitorView {
	if len(views) == 0 {
		return []*service.UserMonitorView{}
	}
	out := make([]*service.UserMonitorView, 0, len(views))
	for _, view := range views {
		if view == nil || !canViewMonitorGroup(view.GroupName, allowed) || !canViewMonitorName(view.Name) {
			continue
		}
		out = append(out, view)
	}
	return out
}

// --- Response ---

type channelMonitorUserListItem struct {
	ID                   int64                                `json:"id"`
	Name                 string                               `json:"name"`
	Provider             string                               `json:"provider"`
	GroupName            string                               `json:"group_name"`
	PrimaryModel         string                               `json:"primary_model"`
	PrimaryStatus        string                               `json:"primary_status"`
	PrimaryLatencyMs     *int                                 `json:"primary_latency_ms"`
	PrimaryPingLatencyMs *int                                 `json:"primary_ping_latency_ms"`
	Availability7d       float64                              `json:"availability_7d"`
	ExtraModels          []dto.ChannelMonitorExtraModelStatus `json:"extra_models"`
	Timeline             []channelMonitorUserTimelinePoint    `json:"timeline"`
}

// channelMonitorUserTimelinePoint 主模型最近一次检测的 timeline 点。
// 仅用于用户视图 list 响应，admin 视图不使用。
type channelMonitorUserTimelinePoint struct {
	Status        string `json:"status"`
	LatencyMs     *int   `json:"latency_ms"`
	PingLatencyMs *int   `json:"ping_latency_ms"`
	CheckedAt     string `json:"checked_at"`
}

type channelMonitorUserDetailResponse struct {
	ID        int64                         `json:"id"`
	Name      string                        `json:"name"`
	Provider  string                        `json:"provider"`
	GroupName string                        `json:"group_name"`
	Models    []channelMonitorUserModelStat `json:"models"`
}

type channelMonitorUserModelStat struct {
	Model           string  `json:"model"`
	LatestStatus    string  `json:"latest_status"`
	LatestLatencyMs *int    `json:"latest_latency_ms"`
	Availability7d  float64 `json:"availability_7d"`
	Availability15d float64 `json:"availability_15d"`
	Availability30d float64 `json:"availability_30d"`
	AvgLatency7dMs  *int    `json:"avg_latency_7d_ms"`
}

func userMonitorViewToItem(v *service.UserMonitorView) channelMonitorUserListItem {
	extras := make([]dto.ChannelMonitorExtraModelStatus, 0, len(v.ExtraModels))
	for _, e := range v.ExtraModels {
		extras = append(extras, dto.ChannelMonitorExtraModelStatus{
			Model:     e.Model,
			Status:    e.Status,
			LatencyMs: e.LatencyMs,
		})
	}
	timeline := make([]channelMonitorUserTimelinePoint, 0, len(v.Timeline))
	for _, p := range v.Timeline {
		timeline = append(timeline, channelMonitorUserTimelinePoint{
			Status:        p.Status,
			LatencyMs:     p.LatencyMs,
			PingLatencyMs: p.PingLatencyMs,
			CheckedAt:     p.CheckedAt.UTC().Format(time.RFC3339),
		})
	}
	return channelMonitorUserListItem{
		ID:                   v.ID,
		Name:                 v.Name,
		Provider:             v.Provider,
		GroupName:            v.GroupName,
		PrimaryModel:         v.PrimaryModel,
		PrimaryStatus:        v.PrimaryStatus,
		PrimaryLatencyMs:     v.PrimaryLatencyMs,
		PrimaryPingLatencyMs: v.PrimaryPingLatencyMs,
		Availability7d:       v.Availability7d,
		ExtraModels:          extras,
		Timeline:             timeline,
	}
}

func userMonitorDetailToResponse(d *service.UserMonitorDetail) *channelMonitorUserDetailResponse {
	models := make([]channelMonitorUserModelStat, 0, len(d.Models))
	for _, m := range d.Models {
		models = append(models, channelMonitorUserModelStat{
			Model:           m.Model,
			LatestStatus:    m.LatestStatus,
			LatestLatencyMs: m.LatestLatencyMs,
			Availability7d:  m.Availability7d,
			Availability15d: m.Availability15d,
			Availability30d: m.Availability30d,
			AvgLatency7dMs:  m.AvgLatency7dMs,
		})
	}
	return &channelMonitorUserDetailResponse{
		ID:        d.ID,
		Name:      d.Name,
		Provider:  d.Provider,
		GroupName: d.GroupName,
		Models:    models,
	}
}

// --- Handlers ---

// List GET /api/v1/channel-monitors
func (h *ChannelMonitorUserHandler) List(c *gin.Context) {
	if !h.featureEnabled(c) {
		response.Success(c, gin.H{"items": []channelMonitorUserListItem{}})
		return
	}
	views, err := h.monitorService.ListUserView(c.Request.Context())
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}
	if !h.isAdmin(c) {
		allowed, ok := h.visibleGroupNames(c)
		if !ok {
			return
		}
		views = filterUserMonitorViewsByGroup(views, allowed)
	}
	items := make([]channelMonitorUserListItem, 0, len(views))
	for _, v := range views {
		items = append(items, userMonitorViewToItem(v))
	}
	response.Success(c, gin.H{"items": items})
}

// GetStatus GET /api/v1/channel-monitors/:id/status
func (h *ChannelMonitorUserHandler) GetStatus(c *gin.Context) {
	if !h.featureEnabled(c) {
		response.ErrorFrom(c, service.ErrChannelMonitorNotFound)
		return
	}
	// 复用 admin.ParseChannelMonitorID 保持错误码与日志一致。
	id, ok := admin.ParseChannelMonitorID(c)
	if !ok {
		return
	}
	detail, err := h.monitorService.GetUserDetail(c.Request.Context(), id)
	if err != nil {
		response.ErrorFrom(c, err)
		return
	}
	if !h.isAdmin(c) {
		allowed, ok := h.visibleGroupNames(c)
		if !ok {
			return
		}
		if !canViewMonitorGroup(detail.GroupName, allowed) || !canViewMonitorName(detail.Name) {
			response.ErrorFrom(c, service.ErrChannelMonitorNotFound)
			return
		}
	}
	response.Success(c, userMonitorDetailToResponse(detail))
}
