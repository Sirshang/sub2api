document.addEventListener("DOMContentLoaded", () => {
  const tabsWrap = document.querySelector(".tabs");
  const indicator = document.querySelector(".tab-indicator");
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

  setActiveTab(document.querySelector("[data-tab].active") || tabs[0]);
  window.addEventListener("resize", () => {
    setActiveTab(document.querySelector("[data-tab].active"));
  });
});
