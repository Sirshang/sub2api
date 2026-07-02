document.addEventListener("DOMContentLoaded", () => {
  const CONFIG_STORAGE_KEY = "rechargePageConfig";
  const tabsWrap = document.querySelector(".tabs");
  const indicator = document.querySelector(".tab-indicator");
  const contactModal = document.querySelector("#contact-modal");
  const openContactModalTrigger = document.querySelector("[data-open-contact-modal]");
  const closeContactModalTriggers = Array.from(document.querySelectorAll("[data-close-contact-modal]"));

  function getConfig() {
    const baseConfig = window.RECHARGE_PAGE_CONFIG || {};
    try {
      const localConfig = JSON.parse(localStorage.getItem(CONFIG_STORAGE_KEY) || "null");
      if (localConfig && typeof localConfig === "object") {
        return {
          ...baseConfig,
          ...localConfig,
          balancePlans: Array.isArray(localConfig.balancePlans) ? localConfig.balancePlans : baseConfig.balancePlans,
          pricingModels: Array.isArray(localConfig.pricingModels) ? localConfig.pricingModels : baseConfig.pricingModels,
          monthlyPlans: Array.isArray(localConfig.monthlyPlans) ? localConfig.monthlyPlans : baseConfig.monthlyPlans,
        };
      }
    } catch {
      localStorage.removeItem(CONFIG_STORAGE_KEY);
    }
    return baseConfig;
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function escapeAttr(value) {
    return escapeHtml(value).replace(/`/g, "&#096;");
  }

  function renderFeature(feature, dotClass = "dot") {
    const color = feature.color || "#94a3b8";
    const pillClass = feature.pillClass ? ` ${escapeAttr(feature.pillClass)}` : "";
    const value = feature.value
      ? `<span class="pill${pillClass}">${escapeHtml(feature.value)}</span>`
      : "";

    return `
      <li class="feature">
        <span class="feature-left"><span class="${dotClass}" style="color: ${escapeAttr(color)}">•</span><span>${escapeHtml(feature.label)}</span></span>
        ${value}
      </li>
    `;
  }

  function renderBalancePlans(config) {
    const target = document.querySelector('[data-view="balance"] .cards');
    const plans = Array.isArray(config.balancePlans) ? config.balancePlans : [];
    if (!target || plans.length === 0) return;

    target.innerHTML = plans
      .map((plan) => {
        const isFeatured = Boolean(plan.featured);
        const badge = plan.badge
          ? `<span class="badge ${isFeatured ? "featured" : "discount"}">${escapeHtml(plan.badge)}</span>`
          : "";
        const oldPrice = plan.oldPrice ? `<div class="old-price">${escapeHtml(plan.oldPrice)}</div>` : "";
        const features = Array.isArray(plan.features) ? plan.features.map((item) => renderFeature(item)).join("") : "";
        const buyText = plan.buyText || "前往购买";
        const buyUrl = plan.buyUrl || "#";

        return `
          <section class="card${isFeatured ? " featured" : ""}">
            ${badge}
            <div class="plan-title">${escapeHtml(plan.title)}</div>
            <div class="price-row">
              <div class="price">${escapeHtml(plan.price)}</div>
              ${oldPrice}
            </div>
            <ul class="feature-list">${features}</ul>
            <a class="buy-btn" href="${escapeAttr(buyUrl)}" target="_blank" rel="noreferrer">${escapeHtml(buyText)}</a>
          </section>
        `;
      })
      .join("");
  }

  function renderMonthlyPlans(config) {
    const target = document.querySelector('[data-view="monthly"] .monthly-grid');
    const plans = Array.isArray(config.monthlyPlans) ? config.monthlyPlans : [];
    if (!target || plans.length === 0) return;

    target.innerHTML = plans
      .map((plan) => {
        const isFeatured = Boolean(plan.featured);
        const badge = plan.badge ? `<div class="monthly-badge">${escapeHtml(plan.badge)}</div>` : "";
        const saveText = plan.saveText ? `<p class="monthly-save">${escapeHtml(plan.saveText)}</p>` : "";
        const features = Array.isArray(plan.features)
          ? plan.features
              .map((feature) => `<li><span class="check">✓</span><span>${escapeHtml(feature)}</span></li>`)
              .join("")
          : "";
        const buyText = plan.buyText || "订阅";
        const buyUrl = plan.buyUrl || "#";

        return `
          <section class="monthly-card${isFeatured ? " featured" : ""}">
            ${badge}
            <div class="monthly-title">${escapeHtml(plan.title)}</div>
            <div class="monthly-price"><strong>${escapeHtml(plan.price)}</strong><span>${escapeHtml(plan.unit || "")}</span></div>
            ${saveText}
            <ul class="monthly-list">${features}</ul>
            <a class="monthly-action" href="${escapeAttr(buyUrl)}" target="_blank" rel="noreferrer">${escapeHtml(buyText)}</a>
          </section>
        `;
      })
      .join("");
  }

  function renderPricingModels(config) {
    const target = document.querySelector('[data-view="pricing"] .pricing-grid');
    const models = Array.isArray(config.pricingModels) ? config.pricingModels : [];
    if (!target || models.length === 0) return;

    target.innerHTML = models
      .map((model) => {
        const providerClass = model.providerClass ? ` ${escapeAttr(model.providerClass)}` : "";
        const contextClass = model.contextClass ? ` ${escapeAttr(model.contextClass)}` : "";
        const rows = Array.isArray(model.rows)
          ? model.rows
              .map(
                (row) => `
                  <div class="pricing-row"><span>${escapeHtml(row.label)}</span><strong>${escapeHtml(row.value)}</strong></div>
                `,
              )
              .join("")
          : "";

        return `
          <section class="pricing-card${model.featured ? " featured" : ""}">
            <div class="pricing-card-head">
              <div>
                <p class="provider${providerClass}">${escapeHtml(model.provider)}</p>
                <h2 class="model-name">${escapeHtml(model.modelName)}</h2>
              </div>
              <span class="context-badge${contextClass}">${escapeHtml(model.context)}</span>
            </div>
            <div class="pricing-rows">${rows}</div>
          </section>
        `;
      })
      .join("");
  }

  const pageConfig = getConfig();
  renderBalancePlans(pageConfig);
  renderPricingModels(pageConfig);
  renderMonthlyPlans(pageConfig);

  const tabs = Array.from(document.querySelectorAll("[data-tab]"));
  const views = Array.from(document.querySelectorAll("[data-view]"));

  function moveIndicator(tab) {
    if (!tabsWrap || !indicator || !tab) return;
    const wrapRect = tabsWrap.getBoundingClientRect();
    const tabRect = tab.getBoundingClientRect();

    indicator.style.width = `${tabRect.width}px`;
    indicator.style.height = `${tabRect.height}px`;
    indicator.style.transform = `translate(${tabRect.left - wrapRect.left}px, ${tabRect.top - wrapRect.top}px)`;
  }

  function setActiveTab(tab) {
    if (!tab) return;
    const target = tab.dataset.tab;

    tabs.forEach((item) => item.classList.toggle("active", item === tab));
    views.forEach((view) => view.classList.toggle("active", view.dataset.view === target));
    moveIndicator(tab);
  }

  tabs.forEach((tab) => {
    tab.addEventListener("click", () => setActiveTab(tab));
  });

  function openContactModal() {
    if (!contactModal) return;
    contactModal.hidden = false;
    document.body.style.overflow = "hidden";
  }

  function closeContactModal() {
    if (!contactModal) return;
    contactModal.hidden = true;
    document.body.style.overflow = "";
  }

  if (openContactModalTrigger) {
    openContactModalTrigger.addEventListener("click", openContactModal);
  }

  closeContactModalTriggers.forEach((trigger) => {
    trigger.addEventListener("click", closeContactModal);
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && contactModal && !contactModal.hidden) {
      closeContactModal();
    }
  });

  setActiveTab(document.querySelector("[data-tab].active") || tabs[0]);
  window.addEventListener("resize", () => {
    setActiveTab(document.querySelector("[data-tab].active"));
  });
});
