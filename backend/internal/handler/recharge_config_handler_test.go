package handler

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestRechargeConfigHandlerUpdateWritesStaticOverride(t *testing.T) {
	gin.SetMode(gin.TestMode)
	dataDir := t.TempDir()
	handler := NewRechargeConfigHandler(dataDir)
	config := validRechargePageConfig()
	body, err := json.Marshal(config)
	if err != nil {
		t.Fatalf("marshal config: %v", err)
	}

	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(http.MethodPut, "/api/v1/admin/custom-pages/recharge-config", bytes.NewReader(body))
	ctx.Request.Header.Set("Content-Type", "application/json")

	handler.Update(ctx)

	if recorder.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", recorder.Code, recorder.Body.String())
	}
	path := filepath.Join(dataDir, "public", "custom-pages", "recharge-config.js")
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read saved config: %v", err)
	}
	text := string(content)
	if !strings.HasPrefix(text, "window.RECHARGE_PAGE_CONFIG = {") {
		t.Fatalf("unexpected config prefix: %q", text)
	}
	if !strings.Contains(text, `"title": "额度$50"`) {
		t.Fatalf("saved config is missing balance plan: %s", text)
	}
	if !strings.HasSuffix(text, ";\n") {
		t.Fatalf("saved config must end with semicolon and newline: %q", text)
	}
}

func TestRechargeConfigHandlerUpdateRejectsUnsafePurchaseURL(t *testing.T) {
	gin.SetMode(gin.TestMode)
	dataDir := t.TempDir()
	handler := NewRechargeConfigHandler(dataDir)
	config := validRechargePageConfig()
	config.BalancePlans[0].BuyURL = "javascript:alert(1)"
	body, err := json.Marshal(config)
	if err != nil {
		t.Fatalf("marshal config: %v", err)
	}

	recorder := httptest.NewRecorder()
	ctx, _ := gin.CreateTestContext(recorder)
	ctx.Request = httptest.NewRequest(http.MethodPut, "/api/v1/admin/custom-pages/recharge-config", bytes.NewReader(body))
	ctx.Request.Header.Set("Content-Type", "application/json")

	handler.Update(ctx)

	if recorder.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", recorder.Code, http.StatusBadRequest)
	}
	path := filepath.Join(dataDir, "public", "custom-pages", "recharge-config.js")
	if _, err := os.Stat(path); !os.IsNotExist(err) {
		t.Fatalf("invalid config should not be written, stat error = %v", err)
	}
}

func validRechargePageConfig() RechargePageConfig {
	return RechargePageConfig{
		BalancePlans: []RechargeBalancePlan{
			{
				Title:   "额度$50",
				Price:   "￥50",
				BuyText: "前往购买",
				BuyURL:  "https://pay.example.com/balance-50",
				Features: []RechargeFeature{
					{Label: "永久不过期", Color: "#94a3b8"},
				},
			},
		},
		PricingModels: []RechargePricingModel{
			{
				Provider:  "OpenAI",
				ModelName: "GPT",
				Rows: []RechargePriceRow{
					{Label: "输入", Value: "$1.00"},
				},
			},
		},
		MonthlyPlans: []RechargeMonthlyPlan{
			{
				Title:    "月套餐",
				Price:    "￥99",
				BuyText:  "订阅",
				BuyURL:   "https://pay.example.com/monthly",
				Features: []string{"月总额度 $100"},
			},
		},
	}
}
