package handler

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/Wei-Shaw/sub2api/internal/pkg/response"
	"github.com/gin-gonic/gin"
)

const maxRechargeConfigSize = 512 << 10

type RechargeConfigHandler struct {
	configPath string
}

type RechargePageConfig struct {
	BalancePlans  []RechargeBalancePlan  `json:"balancePlans"`
	PricingModels []RechargePricingModel `json:"pricingModels"`
	MonthlyPlans  []RechargeMonthlyPlan  `json:"monthlyPlans"`
}

type RechargeBalancePlan struct {
	Title    string            `json:"title"`
	Price    string            `json:"price"`
	OldPrice string            `json:"oldPrice"`
	Badge    string            `json:"badge"`
	Featured bool              `json:"featured"`
	BuyText  string            `json:"buyText"`
	BuyURL   string            `json:"buyUrl"`
	Features []RechargeFeature `json:"features"`
}

type RechargeFeature struct {
	Label     string `json:"label"`
	Value     string `json:"value"`
	Color     string `json:"color"`
	PillClass string `json:"pillClass"`
}

type RechargePricingModel struct {
	Provider      string             `json:"provider"`
	ProviderClass string             `json:"providerClass"`
	ModelName     string             `json:"modelName"`
	Context       string             `json:"context"`
	ContextClass  string             `json:"contextClass"`
	Featured      bool               `json:"featured"`
	Rows          []RechargePriceRow `json:"rows"`
}

type RechargePriceRow struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

type RechargeMonthlyPlan struct {
	Badge    string   `json:"badge"`
	Featured bool     `json:"featured"`
	Title    string   `json:"title"`
	Price    string   `json:"price"`
	Unit     string   `json:"unit"`
	SaveText string   `json:"saveText"`
	BuyText  string   `json:"buyText"`
	BuyURL   string   `json:"buyUrl"`
	Features []string `json:"features"`
}

func NewRechargeConfigHandler(dataDir string) *RechargeConfigHandler {
	return &RechargeConfigHandler{
		configPath: filepath.Join(dataDir, "public", "custom-pages", "recharge-config.js"),
	}
}

// Update writes the public recharge configuration to the persistent static override directory.
func (h *RechargeConfigHandler) Update(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxRechargeConfigSize)

	var config RechargePageConfig
	if err := c.ShouldBindJSON(&config); err != nil {
		response.BadRequest(c, "充值配置格式不正确")
		return
	}
	if err := validateRechargePageConfig(config); err != nil {
		response.BadRequest(c, err.Error())
		return
	}

	content, err := marshalRechargePageConfig(config)
	if err != nil {
		response.InternalError(c, "生成充值配置失败")
		return
	}
	if err := writeFileAtomically(h.configPath, content, 0644); err != nil {
		response.InternalError(c, "保存充值配置失败")
		return
	}

	response.Success(c, gin.H{"updated_at": time.Now().UTC().Format(time.RFC3339)})
}

func validateRechargePageConfig(config RechargePageConfig) error {
	if err := validateRechargeItemCount("余额充值卡片", len(config.BalancePlans)); err != nil {
		return err
	}
	if err := validateRechargeItemCount("模型定价卡片", len(config.PricingModels)); err != nil {
		return err
	}
	if err := validateRechargeItemCount("月套餐卡片", len(config.MonthlyPlans)); err != nil {
		return err
	}

	for i, plan := range config.BalancePlans {
		if strings.TrimSpace(plan.Title) == "" || strings.TrimSpace(plan.Price) == "" {
			return fmt.Errorf("余额充值卡片 %d 的标题和现价不能为空", i+1)
		}
		if err := validateRechargeURL(plan.BuyURL); err != nil {
			return fmt.Errorf("余额充值卡片 %d: %w", i+1, err)
		}
		if len(plan.Features) > 20 {
			return fmt.Errorf("余额充值卡片 %d 的权益不能超过 20 条", i+1)
		}
	}
	for i, model := range config.PricingModels {
		if strings.TrimSpace(model.Provider) == "" || strings.TrimSpace(model.ModelName) == "" {
			return fmt.Errorf("模型定价卡片 %d 的平台和模型名称不能为空", i+1)
		}
		if len(model.Rows) == 0 || len(model.Rows) > 20 {
			return fmt.Errorf("模型定价卡片 %d 的价格项数量应为 1 到 20 条", i+1)
		}
	}
	for i, plan := range config.MonthlyPlans {
		if strings.TrimSpace(plan.Title) == "" || strings.TrimSpace(plan.Price) == "" {
			return fmt.Errorf("月套餐卡片 %d 的标题和价格不能为空", i+1)
		}
		if err := validateRechargeURL(plan.BuyURL); err != nil {
			return fmt.Errorf("月套餐卡片 %d: %w", i+1, err)
		}
		if len(plan.Features) > 20 {
			return fmt.Errorf("月套餐卡片 %d 的权益不能超过 20 条", i+1)
		}
	}

	return nil
}

func validateRechargeItemCount(label string, count int) error {
	if count == 0 || count > 50 {
		return fmt.Errorf("%s数量应为 1 到 50 个", label)
	}
	return nil
}

func validateRechargeURL(raw string) error {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil || parsed.Host == "" || (parsed.Scheme != "http" && parsed.Scheme != "https") {
		return fmt.Errorf("购买链接必须是有效的 http 或 https 地址")
	}
	return nil
}

func marshalRechargePageConfig(config RechargePageConfig) ([]byte, error) {
	encoded, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return nil, err
	}
	content := make([]byte, 0, len(encoded)+40)
	content = append(content, "window.RECHARGE_PAGE_CONFIG = "...)
	content = append(content, encoded...)
	content = append(content, ';', '\n')
	return content, nil
}

func writeFileAtomically(path string, content []byte, mode os.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	tmp, err := os.CreateTemp(dir, ".recharge-config-*.tmp")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer func() { _ = os.Remove(tmpPath) }()

	if err := tmp.Chmod(mode); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(content); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmpPath, path)
}
