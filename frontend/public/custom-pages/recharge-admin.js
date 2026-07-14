const defaultConfig = cloneConfig(window.RECHARGE_PAGE_CONFIG || {});
const balanceEditors = document.querySelector("#balance-editors");
const pricingEditors = document.querySelector("#pricing-editors");
const monthlyEditors = document.querySelector("#monthly-editors");
const statusEl = document.querySelector("#status");
const saveButton = document.querySelector("#save-config");

function cloneConfig(value) {
  return JSON.parse(JSON.stringify(value));
}

function normalizeConfig(value) {
  const candidate = value && typeof value === "object" ? value : {};
  return {
    ...defaultConfig,
    ...candidate,
    balancePlans: Array.isArray(candidate.balancePlans) ? candidate.balancePlans : cloneConfig(defaultConfig.balancePlans || []),
    pricingModels: Array.isArray(candidate.pricingModels) ? candidate.pricingModels : cloneConfig(defaultConfig.pricingModels || []),
    monthlyPlans: Array.isArray(candidate.monthlyPlans) ? candidate.monthlyPlans : cloneConfig(defaultConfig.monthlyPlans || []),
  };
}

let config = normalizeConfig(defaultConfig);

function setStatus(message, type = "success") {
  statusEl.textContent = message;
  statusEl.classList.toggle("error", type === "error");
  statusEl.classList.add("visible");
  window.clearTimeout(setStatus.timer);
  setStatus.timer = window.setTimeout(() => {
    statusEl.classList.remove("visible");
  }, 3600);
}

function escapeAttr(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

function input(label, path, value, placeholder = "") {
  return `
    <label>
      <span>${label}</span>
      <input data-path="${path}" value="${escapeAttr(value)}" placeholder="${escapeAttr(placeholder)}" />
    </label>
  `;
}

function select(label, path, value, options) {
  const optionHtml = options
    .map((option) => `<option value="${escapeAttr(option.value)}" ${value === option.value ? "selected" : ""}>${escapeAttr(option.label)}</option>`)
    .join("");
  return `
    <label>
      <span>${label}</span>
      <select data-path="${path}">${optionHtml}</select>
    </label>
  `;
}

function checkbox(label, path, checked) {
  return `
    <label class="checkline">
      <input type="checkbox" data-path="${path}" ${checked ? "checked" : ""} />
      <span>${label}</span>
    </label>
  `;
}

function deleteButton(type, index, disabled) {
  return `<button class="mini-btn danger" type="button" data-action="delete-${type}" data-index="${index}" ${disabled ? "disabled" : ""}>删除卡片</button>`;
}

function writePath(path, value) {
  const parts = path.split(".");
  const last = parts.pop();
  const target = parts.reduce((item, key) => item[key], config);
  target[last] = value;
}

function getLastOrTemplate(list, template) {
  const source = list.length > 0 ? list[list.length - 1] : template;
  return cloneConfig(source);
}

function createBalancePlan() {
  const template = {
    title: "额度$100",
    price: "￥99",
    oldPrice: "￥100",
    badge: "",
    featured: false,
    buyText: "前往购买",
    buyUrl: "",
    features: [
      { label: "低价 Claude", value: "0.25x", color: "#10b981", pillClass: "green" },
      { label: "特价 OpenAI", value: "0.25x", color: "#f97316", pillClass: "orange" },
      { label: "优质 OpenAI", value: "0.5x", color: "#0b77e3", pillClass: "blue" },
      { label: "按实际使用量扣费", value: "", color: "#94a3b8", pillClass: "" },
      { label: "永久不过期", value: "", color: "#94a3b8", pillClass: "" },
    ],
  };
  const next = getLastOrTemplate(config.balancePlans, template);
  next.title = "新增余额";
  next.price = "￥";
  next.oldPrice = "";
  next.badge = "";
  next.featured = false;
  next.buyUrl = "";
  return next;
}

function createPricingModel() {
  const template = {
    provider: "OpenAI",
    providerClass: "openai",
    modelName: "新增模型",
    context: "1M",
    contextClass: "green",
    featured: false,
    rows: [
      { label: "输入 (Input)", value: "$0.00" },
      { label: "输出 (Output)", value: "$0.00" },
      { label: "缓存读取 (Cache Read)", value: "$0.00" },
      { label: "缓存写入 (Cache Write)", value: "$0.00" },
    ],
  };
  const next = getLastOrTemplate(config.pricingModels, template);
  next.modelName = "新增模型";
  next.featured = false;
  return next;
}

function createMonthlyPlan() {
  const template = {
    badge: "",
    featured: false,
    title: "新增月套餐",
    price: "￥",
    unit: "/月",
    saveText: "",
    buyText: "订阅",
    buyUrl: "",
    features: ["月总额度 $1000", "日上限 $1000", "周上限 $1000", "倍率 0.4 x"],
  };
  const next = getLastOrTemplate(config.monthlyPlans, template);
  next.badge = "";
  next.featured = false;
  next.title = "新增月套餐";
  next.price = "￥";
  next.buyUrl = "";
  return next;
}

function renderBalanceEditors() {
  balanceEditors.innerHTML = config.balancePlans
    .map((plan, planIndex) => {
      const features = (plan.features || [])
        .map((feature, featureIndex) => {
          const base = `balancePlans.${planIndex}.features.${featureIndex}`;
          return `
            <div class="feature-row">
              ${input(`权益 ${featureIndex + 1}`, `${base}.label`, feature.label)}
              ${input("倍率/标签", `${base}.value`, feature.value)}
              ${select("颜色", `${base}.pillClass`, feature.pillClass || "", [
                { value: "", label: "灰色/无标签" },
                { value: "green", label: "绿色" },
                { value: "orange", label: "橙色" },
                { value: "blue", label: "蓝色" },
              ])}
            </div>
          `;
        })
        .join("");

      return `
        <div class="plan-editor">
          <div class="plan-head">
            <strong>余额卡 ${planIndex + 1}</strong>
            <div class="mini-actions">
              ${checkbox("推荐高亮", `balancePlans.${planIndex}.featured`, plan.featured)}
              ${deleteButton("balance", planIndex, config.balancePlans.length <= 1)}
            </div>
          </div>
          <div class="fields">
            ${input("标题", `balancePlans.${planIndex}.title`, plan.title, "余额 $100")}
            ${input("现价", `balancePlans.${planIndex}.price`, plan.price, "￥99")}
            ${input("划线价", `balancePlans.${planIndex}.oldPrice`, plan.oldPrice, "￥100")}
            ${input("角标", `balancePlans.${planIndex}.badge`, plan.badge, "省1% / 推荐")}
            ${input("按钮文字", `balancePlans.${planIndex}.buyText`, plan.buyText, "前往购买")}
            ${input("购买链接", `balancePlans.${planIndex}.buyUrl`, plan.buyUrl, "https://...")}
          </div>
          <div class="feature-fields">${features}</div>
        </div>
      `;
    })
    .join("");
}

function renderPricingEditors() {
  pricingEditors.innerHTML = config.pricingModels
    .map((model, modelIndex) => {
      const base = `pricingModels.${modelIndex}`;
      const rows = (model.rows || [])
        .map((row, rowIndex) => {
          const rowBase = `${base}.rows.${rowIndex}`;
          return `
            <div class="pricing-row-editor">
              ${input(`价格项 ${rowIndex + 1}`, `${rowBase}.label`, row.label, "输入 (Input)")}
              ${input("价格", `${rowBase}.value`, row.value, "$5.00")}
            </div>
          `;
        })
        .join("");

      return `
        <div class="plan-editor">
          <div class="plan-head">
            <strong>模型卡 ${modelIndex + 1}</strong>
            <div class="mini-actions">
              ${checkbox("推荐高亮", `${base}.featured`, model.featured)}
              ${deleteButton("pricing", modelIndex, config.pricingModels.length <= 1)}
            </div>
          </div>
          <div class="fields">
            ${input("平台", `${base}.provider`, model.provider, "OpenAI / Anthropic")}
            ${select("平台颜色", `${base}.providerClass`, model.providerClass || "", [
              { value: "", label: "紫色" },
              { value: "openai", label: "绿色" },
            ])}
            ${input("模型名称", `${base}.modelName`, model.modelName, "GPT-5.5")}
            ${input("上下文/标签", `${base}.context`, model.context, "1M / 200K~1M")}
            ${select("标签颜色", `${base}.contextClass`, model.contextClass || "", [
              { value: "", label: "紫色" },
              { value: "green", label: "绿色" },
            ])}
          </div>
          <div class="feature-fields">${rows}</div>
        </div>
      `;
    })
    .join("");
}

function renderMonthlyEditors() {
  monthlyEditors.innerHTML = config.monthlyPlans
    .map((plan, planIndex) => {
      const base = `monthlyPlans.${planIndex}`;
      const features = (plan.features || [])
        .map((feature, featureIndex) => input(`权益 ${featureIndex + 1}`, `${base}.features.${featureIndex}`, feature))
        .join("");

      return `
        <div class="plan-editor">
          <div class="plan-head">
            <strong>月套餐 ${planIndex + 1}</strong>
            <div class="mini-actions">
              ${checkbox("推荐高亮", `${base}.featured`, plan.featured)}
              ${deleteButton("monthly", planIndex, config.monthlyPlans.length <= 1)}
            </div>
          </div>
          <div class="fields">
            ${input("角标", `${base}.badge`, plan.badge, "推荐")}
            ${input("标题", `${base}.title`, plan.title, "OpenAI大月卡")}
            ${input("价格", `${base}.price`, plan.price, "￥989")}
            ${input("单位", `${base}.unit`, plan.unit, "/月")}
            ${input("红色说明", `${base}.saveText`, plan.saveText, "比余额充值剩25%")}
            ${input("按钮文字", `${base}.buyText`, plan.buyText, "订阅")}
            ${input("购买链接", `${base}.buyUrl`, plan.buyUrl, "https://...")}
          </div>
          <div class="feature-fields">${features}</div>
        </div>
      `;
    })
    .join("");
}

function updateColorForFeature(path, pillClass) {
  if (!path.includes(".pillClass")) return;
  const colorPath = path.replace(".pillClass", ".color");
  const colorMap = {
    green: "#10b981",
    orange: "#f97316",
    blue: "#0b77e3",
    "": "#94a3b8",
  };
  writePath(colorPath, colorMap[pillClass] || "#94a3b8");
}

function bindEditors() {
  document.querySelectorAll("[data-path]").forEach((field) => {
    field.addEventListener("input", () => {
      const value = field.type === "checkbox" ? field.checked : field.value;
      writePath(field.dataset.path, value);
      updateColorForFeature(field.dataset.path, value);
    });
  });
}

function render() {
  renderBalanceEditors();
  renderPricingEditors();
  renderMonthlyEditors();
  bindEditors();
}

document.addEventListener("click", (event) => {
  const action = event.target?.dataset?.action;
  if (!action) return;

  if (action === "add-balance") {
    config.balancePlans.push(createBalancePlan());
  } else if (action === "add-pricing") {
    config.pricingModels.push(createPricingModel());
  } else if (action === "add-monthly") {
    config.monthlyPlans.push(createMonthlyPlan());
  } else if (action === "delete-balance" && config.balancePlans.length > 1) {
    config.balancePlans.splice(Number(event.target.dataset.index), 1);
  } else if (action === "delete-pricing" && config.pricingModels.length > 1) {
    config.pricingModels.splice(Number(event.target.dataset.index), 1);
  } else if (action === "delete-monthly" && config.monthlyPlans.length > 1) {
    config.monthlyPlans.splice(Number(event.target.dataset.index), 1);
  } else {
    return;
  }

  render();
});

saveButton.addEventListener("click", async () => {
  const token = localStorage.getItem("auth_token");
  if (!token) {
    setStatus("请先登录管理员后台，再保存充值配置。", "error");
    return;
  }

  const originalText = saveButton.textContent;
  saveButton.disabled = true;
  saveButton.textContent = "保存中...";

  try {
    const response = await fetch("/api/v1/admin/custom-pages/recharge-config", {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(config),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok || result.code !== 0) {
      if (response.status === 401 || response.status === 403) {
        throw new Error("管理员登录已失效，请重新登录后再保存。");
      }
      throw new Error(result.message || "保存失败，请稍后重试。");
    }
    setStatus("保存成功，充值页已立即更新。");
  } catch (error) {
    setStatus(error.message || "保存失败，请稍后重试。", "error");
  } finally {
    saveButton.disabled = false;
    saveButton.textContent = originalText;
  }
});

render();
