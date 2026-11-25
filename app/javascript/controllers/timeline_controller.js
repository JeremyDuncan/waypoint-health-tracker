import { Controller } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["canvas", "content", "scroll", "mode", "weightToggle", "trendToggle", "injectionToggle", "noteToggle", "injectionRow", "noteRow", "explanation"]
  static values = { payload: Object }
  connect() {
    this.themeChanged = () => this.render()
    window.addEventListener("waypoint-health:theme-change", this.themeChanged)
    this.resizeObserver = new ResizeObserver(() => this.layout())
    this.resizeObserver.observe(this.scrollTarget)
    this.layout()
    this.modeTarget.disabled = false
  }
  disconnect() {
    window.removeEventListener("waypoint-health:theme-change", this.themeChanged)
    this.resizeObserver?.disconnect()
    this.chart?.destroy()
  }
  layout() {
    const width = Math.max(280, this.scrollTarget.clientWidth)
    this.contentTarget.style.width = `${width}px`
    this.render()
  }
  change() {
    this.render()
    this.dispatch("preferences", { detail: { mode: this.modeTarget.value, trend: this.trendToggleTarget.checked, weight: this.weightToggleTarget.checked, injections: this.injectionToggleTarget.checked, notes: this.noteToggleTarget.checked } })
  }
  render() {
    if (!globalThis.Chart) return
    const p = this.payloadValue
    const style = getComputedStyle(document.documentElement)
    const color = name => style.getPropertyValue(name).trim()
    const mode = this.modeTarget.value
    const averaged = mode !== "raw"
    const data = p[mode]
    const showTrend = this.hasTrendToggleTarget && this.trendToggleTarget.checked
    const trend = p.trend || []
    const hasValues = (this.weightToggleTarget.checked && data.length > 0) || (showTrend && trend.length > 0)
    const showInjections = this.injectionToggleTarget.checked
    const compact = this.compact
    const lane = this.laneSize
    const availableWidth = Math.max(1, this.contentTarget.clientWidth - (compact ? 60 : 180))
    const lanes = this.injectionLanes(showInjections ? p.injections : [], event => (event.x - p.from) / (p.to - p.from) * availableWidth)
    const laneCount = Math.max(0, ...lanes.map(item => item.lane + 1))
    this.canvasTarget.parentElement.style.height = `${(this.scrollTarget.clientWidth < 700 ? 220 : 265) + laneCount * lane.height}px`
    this.explanationTarget.textContent = {
      raw: "Each point is a weigh-in.",
      weekly: "Average per Monday–Sunday week.",
      monthly: "Average per calendar month."
    }[mode]
    if (showTrend) this.explanationTarget.textContent += " Dashed: average of the last 7 days."
    this.chart?.destroy()
    this.chart = new globalThis.Chart(this.canvasTarget, {
      type: "line",
      data: { datasets: [{ data, label: mode === "raw" ? "Weight" : `${mode === "weekly" ? "Weekly" : "Monthly"} average`, hidden: !this.weightToggleTarget.checked, borderColor: color("--chart-line"), backgroundColor: context => this.weightGradient(context.chart, color("--chart-line")), fill: "start", pointBackgroundColor: color("--chart-line"), borderWidth: 2.5, pointRadius: 4, pointHoverRadius: 7, pointHitRadius: 15, pointBorderColor: color("--card"), pointBorderWidth: 2, cubicInterpolationMode: "monotone", tension: 0.35, spanGaps: false }, ...(showTrend ? [{ data: trend, label: "7-day rolling trend", borderColor: color("--injection-ink"), backgroundColor: color("--injection-ink"), borderWidth: 2.5, borderDash: [6, 5], pointRadius: 2, pointHitRadius: 10, cubicInterpolationMode: "monotone", tension: 0.35, spanGaps: false }] : [])] },
      options: {
        animation: false, responsive: true, maintainAspectRatio: false, parsing: false,
        layout: { padding: { left: hasValues ? (compact ? 4 : 27) : (compact ? 16 : 60), right: compact ? 16 : 60, top: (compact ? 14 : 20) + laneCount * lane.height, bottom: 5 } },
        plugins: { legend: { display: false }, tooltip: { backgroundColor: color("--card"), titleColor: color("--ink"), bodyColor: color("--ink"), borderColor: color("--line"), borderWidth: 1, callbacks: {
          title: items => items.length ? this.readingTime(items[0].raw.x) : "",
          label: item => `${item.dataset.label}: ${item.raw.y.toFixed(2)} ${p.unit}${averaged || item.datasetIndex === 1 ? ` · ${item.raw.count} readings` : ""}`,
          afterBody: items => items.length ? p.injections.filter(event => event.day === items[0].raw.day).map(event => `Shot: ${event.label} · ${this.readingTime(event.x)}`) : []
        } } },
        scales: {
          x: { type: "linear", min: p.from, max: p.to, grid: { display: false }, border: { display: false },
            afterBuildTicks: scale => {
              if (!p.days?.length) return
              const limit = Math.max(1, Math.floor((this.contentTarget.clientWidth - 110) / (this.scrollTarget.clientWidth < 500 ? 28 : 75)))
              const stride = Math.max(1, Math.ceil(p.days.length / limit))
              scale.ticks = p.days.filter((_, index) => index % stride === 0).map(day => ({ value: day.noon }))
            },
            ticks: { autoSkip: !p.days?.length, maxRotation: 0, maxTicksLimit: this.scrollTarget.clientWidth < 500 ? 4 : 7, color: color("--chart-label"), font: { size: this.scrollTarget.clientWidth < 500 ? 9 : 11 }, callback: value => this.dateLabel(value) } },
          y: { title: { display: hasValues && !compact, text: p.unit, color: color("--chart-label") }, grace: "12%", grid: { color: color("--chart-grid") }, border: { display: false }, ticks: { display: hasValues, color: color("--chart-label"), maxTicksLimit: compact ? 4 : 5, font: { size: compact ? 10 : 11 } } }
        },
        onClick: (_, elements) => { if (elements.length) { const point = elements[0]; this.openDay((point.datasetIndex === 1 ? trend : data)[point.index]?.day) } }
      },
      plugins: [{ id: "localDayContext", beforeDatasetsDraw: chart => {
        const area = chart.chartArea, ctx = chart.ctx
        ctx.save(); ctx.beginPath(); ctx.rect(area.left, area.top, area.width, area.height); ctx.clip()
        for (const day of p.days || []) {
          const left = chart.scales.x.getPixelForValue(day.start), right = chart.scales.x.getPixelForValue(day.finish)
          if (day.weekend) { ctx.fillStyle = color("--chart-grid"); ctx.globalAlpha = 0.2; ctx.fillRect(left, area.top, right - left, area.height); ctx.globalAlpha = 1 }
          ctx.strokeStyle = color("--chart-grid"); ctx.lineWidth = 0.7; ctx.beginPath(); ctx.moveTo(left, area.top); ctx.lineTo(left, area.bottom); ctx.stroke()
        }
        ctx.restore()
      } }]
    })
    this.chart.update("none")
    this.drawInjections(data)
    this.drawEvents(this.noteRowTarget, p.notes, this.noteToggleTarget.checked, "journal")
  }
  dateLabel(value) {
    const compact = this.scrollTarget.clientWidth < 500 && this.payloadValue.days?.length > 0 && this.payloadValue.days.length <= 14
    const options = { timeZone: this.payloadValue.zone, month: compact ? "numeric" : "short", day: "numeric" }
    if (this.payloadValue.to - this.payloadValue.from > 366 * 86400000) options.year = "numeric"
    const date = new Intl.DateTimeFormat("en-US", options).format(value)
    return this.payloadValue.to - this.payloadValue.from <= 90 * 86400000 ? [new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, weekday: "short" }).format(value), date] : date
  }
  readingTime(value) { return new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, weekday: "long", year: "numeric", month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short" }).format(value) }
  weightGradient(chart, color) {
    const area = chart.chartArea
    if (!area) return `${color}22`
    const gradient = chart.ctx.createLinearGradient(0, area.top, 0, area.bottom)
    gradient.addColorStop(0, `${color}60`)
    gradient.addColorStop(0.65, `${color}20`)
    gradient.addColorStop(1, `${color}00`)
    return gradient
  }
  doseClass(event) { return `dose-${String(Number(event.dose)).replace(".", "-")}` }
  // Phones get short dose-only pills so stacked labels don't push the chart off screen.
  get compact() { return this.scrollTarget.clientWidth < 500 }
  get laneSize() { return this.compact ? { half: 27, height: 30 } : { half: 56, height: 62 } }
  injectionLanes(events, toPixel) {
    const occupied = []
    const { half } = this.laneSize
    return events.map(event => {
      const x = toPixel(event)
      let lane = occupied.findIndex(end => x - half > end + 6)
      if (lane < 0) lane = occupied.length
      occupied[lane] = x + half
      return { event, x, lane }
    })
  }
  drawInjections(data) {
    const layer = this.injectionRowTarget
    layer.replaceChildren()
    layer.hidden = !this.injectionToggleTarget.checked
    if (layer.hidden) return
    const area = this.chart.chartArea
    const points = this.chart.getDatasetMeta(0).data
    const events = this.injectionLanes(this.payloadValue.injections, event => this.chart.scales.x.getPixelForValue(event.x))
    events.forEach(({ event, x, lane }) => {
      const guide = document.createElement("span")
      guide.className = `injection-guide ${this.doseClass(event)}`
      const top = this.compact ? 14 : 20
      guide.style.left = `${x}px`; guide.style.top = `${top}px`; guide.style.height = `${area.bottom - top}px`
      guide.setAttribute("aria-hidden", "true")
      const label = document.createElement("button")
      label.type = "button"; label.className = `event-marker injection injection-dose ${this.doseClass(event)}${this.compact ? " compact" : ""}`
      label.style.left = `${x}px`; label.style.top = `${top + lane * this.laneSize.height}px`
      for (const [kind, text] of [["dose", event.label], ["date", new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, weekday: "short", month: "short", day: "numeric" }).format(event.x)], ["time", new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, hour: "numeric", minute: "2-digit", timeZoneName: "short" }).format(event.x)]]) {
        const span = document.createElement("span"); span.className = `shot-label-${kind}`; span.textContent = text; label.append(span)
      }
      const time = this.readingTime(event.x)
      label.title = `${time} · ${event.label} · ${[event.site, event.side].filter(Boolean).join(" / ") || "Site not recorded"} · actual injection`
      label.setAttribute("aria-label", `${time}: ${event.label} injection. Open day details.`)
      label.addEventListener("click", () => this.openDay(event.day))
      layer.append(guide, label)

      // Position an annotation on the existing drawn line, without creating a
      // medication dataset, a new weight point, or a weight value for the event.
      if (!this.weightToggleTarget.checked || data.length === 0) return
      const right = data.findIndex(point => point.x >= event.x)
      let y
      if (right >= 0 && data[right].x === event.x) {
        y = points[right].y
      } else if (right > 0) {
        y = this.chart.getDatasetMeta(0).dataset.interpolate({ x }, "x")?.y
      }
      if (!Number.isFinite(y)) return
      const marker = document.createElement("button")
      marker.type = "button"; marker.className = `injection-on-line ${this.doseClass(event)}`
      marker.style.left = `${x}px`; marker.style.top = `${y}px`
      marker.title = label.title
      marker.setAttribute("aria-label", `${event.day}: ${event.label} injection on the displayed timeline. Open day details.`)
      marker.addEventListener("click", () => this.openDay(event.day))
      layer.append(marker)
    })
  }
  drawEvents(row, events, visible, kind) {
    row.replaceChildren()
    row.parentElement.hidden = !visible
    if (!visible) return
    const lanes = []
    events.forEach(event => {
      const x = this.chart.scales.x.getPixelForValue(event.x)
      const markerWidth = kind === "journal" ? 64 : 78
      let lane = lanes.findIndex(end => x - markerWidth / 2 > end + 5)
      if (lane < 0) lane = lanes.length
      lanes[lane] = x + markerWidth / 2
      const stem = document.createElement("span")
      stem.className = `event-stem ${kind}`
      stem.style.left = `${x}px`; stem.style.height = `${13 + lane * 36}px`
      const button = document.createElement("button")
      button.type = "button"; button.className = `event-marker ${kind}`
      button.style.left = `${x}px`; button.style.top = `${12 + lane * 36}px`
      button.textContent = kind === "journal" ? "▤ Note" : event.label
      button.title = `${event.day} · ${event.label}`
      button.setAttribute("aria-label", `${event.day}: ${event.label}. Open day details.`)
      button.addEventListener("click", () => this.openDay(event.day))
      row.append(stem, button)
    })
    row.style.height = `${Math.max(1, lanes.length) * 36 + 20}px`
    if (!events.length) {
      const empty = document.createElement("span"); empty.className = "empty-row"
      empty.textContent = kind === "journal" ? "No journal entries in this range" : "No injections logged in this range"
      row.append(empty)
    }
  }
  openDay(day) { if (day) globalThis.Turbo.visit(`/journal/${encodeURIComponent(day)}`) }
}
