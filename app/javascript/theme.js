// Loaded before styles so a remembered theme is applied before the first paint.
// Only this appearance preference is stored locally; never health data or drafts.
(() => {
  const key = "waypoint-health.theme"
  const choices = ["system", "light", "dark"]
  const root = document.documentElement

  function preference() {
    try {
      const saved = localStorage.getItem(key) || localStorage.getItem("hearth.theme")
      return choices.includes(saved) ? saved : "system"
    } catch (_) {
      return root.dataset.themePreference || "system"
    }
  }

  function apply(choice = preference()) {
    const selected = choices.includes(choice) ? choice : "system"
    const dark = selected === "dark" || (selected === "system" && matchMedia("(prefers-color-scheme: dark)").matches)
    root.dataset.theme = dark ? "dark" : "light"
    root.dataset.themePreference = selected
    const color = document.querySelector('meta[name="theme-color"]')
    if (color) color.content = dark ? "#111a16" : "#f6f7f2"
    window.dispatchEvent(new CustomEvent("waypoint-health:theme-change", { detail: { preference: selected, theme: root.dataset.theme } }))
    return selected
  }

  function set(choice) {
    const selected = choices.includes(choice) ? choice : "system"
    try { localStorage.setItem(key, selected) } catch (_) { /* Still works for this open tab. */ }
    apply(selected)
  }

  window.WaypointTheme = { apply, set, preference }
  apply()
})()
