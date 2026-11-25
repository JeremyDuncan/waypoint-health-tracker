import { Controller } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["range", "trajectory", "trajectoryCaption", "trajectoryKey", "doseLegend", "timelineMode", "timelineTitle", "timelineExplanation", "calendarEvents", "shots", "shotWrap", "sites", "siteWrap", "doses", "doseWrap"]
  static values = { payload: Object }

  connect() {
    this.charts = []
    this.themeChanged = () => this.render()
    window.addEventListener("waypoint-health:theme-change", this.themeChanged)
    this.render()
    if (this.hasTimelineModeTarget) this.timelineModeTarget.disabled = false
  }

  disconnect() {
    window.removeEventListener("waypoint-health:theme-change", this.themeChanged)
    this.charts.forEach(chart => chart.destroy())
  }
  changeMode() {
    this.render()
    this.dispatch("preferences", { detail: { mode: this.timelineModeTarget.value } })
  }

  render() {
    if (!globalThis.Chart || !this.hasShotsTarget) return
    this.charts.forEach(chart => chart.destroy())
    this.charts = []
    const style = getComputedStyle(document.documentElement)
    this.color = name => style.getPropertyValue(name).trim()
    this.renderTrajectories()
    this.renderShots()
    this.renderComparison(this.sitesTarget, this.siteWrapTarget, this.payloadValue.sites, true)
    this.renderComparison(this.dosesTarget, this.doseWrapTarget, this.payloadValue.doses, false)
  }

  siteColor(site) {
    return this.color({ "Abdomen": "--chart-line", "Thigh": "--injection-ink", "Upper arm": "--site-arm" }[site] || "--muted")
  }

  options() {
    return {
      animation: false, responsive: true, maintainAspectRatio: false,
      plugins: { legend: { display: false }, tooltip: { backgroundColor: this.color("--card"), titleColor: this.color("--ink"), bodyColor: this.color("--ink"), borderColor: this.color("--line"), borderWidth: 1 } },
      scales: {
        x: { grid: { color: this.color("--chart-grid") }, border: { display: false }, ticks: { color: this.color("--chart-label"), font: { size: 11 } } },
        y: { grid: { color: this.color("--chart-grid") }, border: { display: false }, ticks: { color: this.color("--chart-label"), font: { size: 11 } } }
      }
    }
  }

  empty(canvas, message, available) {
    const parent = canvas.parentElement
    parent.querySelector(".insights-chart-empty")?.remove()
    canvas.hidden = !available
    if (available) return false
    const text = document.createElement("p")
    text.className = "insights-chart-empty muted"
    text.textContent = message
    parent.append(text)
    return true
  }

  doseKey(dose) { return `dose-${String(Number(dose)).replace(".", "-")}` }
  doseColor(dose) { return this.color(`--${this.doseKey(dose)}`) || this.color("--muted") }

  renderTrajectories() {
    this.calendarEventsTarget.replaceChildren()
    const calendar = this.timelineModeTarget.value === "calendar"
    this.trajectoryKeyTarget.hidden = calendar
    this.doseLegendTarget.hidden = !calendar
    this.trajectoryKeyTarget.replaceChildren()
    if (calendar) return this.renderCalendar()
    this.trajectoryTarget.parentElement.style.height = ""
    this.timelineTitleTarget.textContent = "Weight change after each shot"
    this.trajectoryTarget.setAttribute("aria-label", "Weight change after each shot, aligned so day zero is the injection. Each line is listed below with its date, dose, location and change.")
    const data = this.payloadValue.trajectories
    this.timelineExplanationTarget.textContent = data.length ? "Each line is one shot. Below zero means weight lost since that shot’s baseline." : ""
    this.trajectoryCaptionTarget.textContent = data.length ? "Color is dose; stronger is newer. Dashed is in progress. Select a shot to highlight it." : ""
    if (this.empty(this.trajectoryTarget, "Log a weight before and after a shot to compare it here.", data.length > 0)) return
    const unit = this.payloadValue.unit, compact = this.compact
    const options = this.options()
    const allPoints = data.flatMap(shot => shot.points)
    options.scales.x.type = "linear"
    options.scales.x.min = Math.min(-3, ...allPoints.map(point => point.x))
    options.scales.x.max = Math.max(7, ...allPoints.map(point => point.x))
    options.scales.x.title = { display: true, text: "Days from shot", color: this.color("--muted") }
    options.scales.x.grid.display = false
    options.scales.x.ticks.stepSize = 1
    options.scales.x.ticks.maxTicksLimit = 20
    options.scales.x.ticks.autoSkip = false
    options.scales.x.ticks.maxRotation = 0
    if (compact) options.scales.x.afterBuildTicks = scale => { scale.ticks = scale.ticks.filter(tick => tick.value % 2 === 0) }
    options.scales.x.ticks.callback = value => !Number.isInteger(value) ? "" : value === 0 ? "Shot" : value > 0 ? `+${value}` : value
    options.scales.y.title = { display: !compact, text: `Change (${unit})`, color: this.color("--muted") }
    options.scales.y.suggestedMin = 0
    options.scales.y.suggestedMax = 0
    options.scales.y.grace = "15%"
    options.scales.y.ticks.callback = value => `${value > 0 ? "+" : ""}${Number(value.toFixed(1))}`
    options.interaction = { mode: "nearest", intersect: true }
    options.plugins.tooltip.callbacks = {
      title: items => `${this.shortDate(data[items[0].datasetIndex])} · ${Number(data[items[0].datasetIndex].dose)} mg`,
      label: item => {
        const shot = data[item.datasetIndex]
        return [`${shot.site} · ${shot.side}`, `${this.signed(item.raw.y)} ${unit} from baseline`, `Measured: ${item.raw.value.toFixed(2)} ${unit}`, this.date(item.raw.at)]
      }
    }
    options.onClick = (_, elements) => { if (elements.length) this.openShot(data[elements[0].datasetIndex].id) }
    options.onHover = (_, elements) => this.emphasize(elements.length ? elements[0].datasetIndex : this.pinned)
    options.layout = { padding: { top: 20, right: compact ? 12 : 52 } }
    this.pinned = null
    this.emphasized = undefined
    // Shots at the same dose share its hue: the newest is full strength and older ones are paler.
    const shapes = ["circle", "triangle", "rect", "rectRot", "star"], perDose = {}, totals = {}
    data.forEach(shot => { totals[shot.dose] = (totals[shot.dose] || 0) + 1 })
    const styled = data.map(shot => {
      const nth = perDose[shot.dose] = (perDose[shot.dose] ?? -1) + 1
      return { shot, color: this.blend(this.doseColor(shot.dose), totals[shot.dose] > 1 ? 0.45 + 0.55 * nth / (totals[shot.dose] - 1) : 1), shape: shapes[nth % shapes.length], dash: shot.status === "open" ? [5, 4] : [] }
    })
    this.trajectoryChart = new globalThis.Chart(this.trajectoryTarget, {
      type: "line", options, plugins: [this.trajectoryContext(), this.endLabels(data)],
      data: { datasets: styled.map(({ shot, color, shape, dash }) => ({ label: this.shortDate(shot), data: shot.points, parsing: false,
        baseColor: color, borderColor: color, backgroundColor: color, borderWidth: 2, pointStyle: shape, pointRadius: shape === "circle" ? 5 : 6.5, pointBackgroundColor: color, clip: 10, pointHitRadius: 12, pointHoverRadius: 7,
        pointBorderColor: shape === "star" ? color : this.color("--card"), pointBorderWidth: 1.5, cubicInterpolationMode: "monotone", tension: 0.35, spanGaps: false, borderDash: dash })) }
    })
    this.charts.push(this.trajectoryChart)
    // Newest first, matching the shot history.
    styled.map((style, index) => ({ ...style, index })).reverse().forEach(style => this.trajectoryKeyTarget.append(this.trajectoryKeyItem(style)))
    this.emphasize(null)
  }

  // Mixes a hex color into the card background.
  blend(color, strength) {
    const channels = hex => [1, 3, 5].map(start => parseInt(hex.length === 4 ? hex[(start + 1) / 2].repeat(2) : hex.slice(start, start + 2), 16))
    const base = channels(this.color("--card"))
    return `#${channels(color).map((channel, index) => Math.round(channel * strength + base[index] * (1 - strength)).toString(16).padStart(2, "0")).join("")}`
  }

  trajectoryKeyItem({ shot, color, shape, dash, index }) {
    const item = document.createElement("li"), button = document.createElement("button")
    button.type = "button"; button.className = this.doseKey(shot.dose); button.setAttribute("aria-pressed", "false"); button.dataset.index = index
    const swatch = document.createElement("canvas"), ratio = globalThis.devicePixelRatio || 1
    swatch.width = 34 * ratio; swatch.height = 16 * ratio; swatch.setAttribute("aria-hidden", "true")
    const ctx = swatch.getContext("2d")
    ctx.scale(ratio, ratio); ctx.strokeStyle = ctx.fillStyle = color; ctx.lineWidth = 2; ctx.setLineDash(dash)
    ctx.beginPath(); ctx.moveTo(1, 8); ctx.lineTo(33, 8); ctx.stroke(); ctx.setLineDash([])
    globalThis.Chart.helpers.drawPoint(ctx, { pointStyle: shape, radius: 5, rotation: 0, borderWidth: shape === "star" ? 1.5 : 0 }, 17, 8)
    const text = document.createElement("span"), detail = document.createElement("small"), change = document.createElement("strong")
    text.textContent = `${this.shortDate(shot)} · ${Number(shot.dose)} mg`
    detail.textContent = [shot.site, shot.side, shot.status === "open" ? "In progress" : "Not recorded"].filter(part => part !== "Not recorded").join(" · ")
    change.textContent = `${this.signed(shot.change, 1)} ${this.payloadValue.unit}`
    text.append(detail); button.append(swatch, text, change); item.append(button)
    button.addEventListener("click", () => { this.pinned = this.pinned === index ? null : index; this.emphasize(this.pinned, true) })
    button.addEventListener("mouseenter", () => this.emphasize(index))
    button.addEventListener("mouseleave", () => this.emphasize(this.pinned))
    button.addEventListener("focus", () => this.emphasize(index))
    button.addEventListener("blur", () => this.emphasize(this.pinned))
    return item
  }

  // Brings one shot forward and fades the rest; null shows every line evenly.
  emphasize(index, force = false) {
    if (this.emphasized === index && !force) return
    this.emphasized = index
    const chart = this.trajectoryChart
    chart.data.datasets.forEach((dataset, position) => {
      const faded = index !== null && position !== index
      dataset.borderColor = dataset.backgroundColor = dataset.pointBackgroundColor = faded ? `${dataset.baseColor}30` : dataset.baseColor
      dataset.borderWidth = position === index ? 4 : 2
      dataset.order = position === index ? -1 : chart.data.datasets.length - position
    })
    this.trajectoryKeyTarget.querySelectorAll("button").forEach(button => button.setAttribute("aria-pressed", String(Number(button.dataset.index) === this.pinned)))
    chart.update("none")
  }

  // Shades the days before the shot and marks the baseline every line starts from.
  trajectoryContext() {
    return { id: "trajectoryContext", beforeDatasetsDraw: chart => {
      const { ctx, chartArea: area, scales } = chart, x = scales.x.getPixelForValue(0), zero = scales.y.getPixelForValue(0)
      ctx.save()
      ctx.fillStyle = this.color("--chart-grid"); ctx.globalAlpha = 0.45; ctx.fillRect(area.left, area.top, x - area.left, area.height); ctx.globalAlpha = 1
      ctx.strokeStyle = this.color("--muted"); ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(area.left, zero); ctx.lineTo(area.right, zero); ctx.stroke()
      ctx.setLineDash([4, 4]); ctx.beginPath(); ctx.moveTo(x, area.top); ctx.lineTo(x, area.bottom); ctx.stroke(); ctx.setLineDash([])
      ctx.fillStyle = this.color("--muted"); ctx.font = "11px system-ui"
      ctx.textAlign = "right"; ctx.fillText("Before shot", x - 6, area.top - 7)
      ctx.textAlign = "left"; ctx.fillText("After shot", x + 6, area.top - 7)
      if (zero - area.top > 34) ctx.fillText("▲ gained", area.left + 6, area.top + 15)
      if (area.bottom - zero > 34) ctx.fillText("▼ lost", area.left + 6, area.bottom - 8)
      ctx.restore()
    } }
  }

  // Dates at the line ends. Crowded labels give way to newer shots; phones label only the highlighted one.
  endLabels(data) {
    return { id: "trajectoryEndLabels", afterDatasetsDraw: chart => {
      const ctx = chart.ctx, taken = []
      ctx.save(); ctx.font = "600 11px system-ui"; ctx.fillStyle = this.color("--ink"); ctx.textBaseline = "middle"
      const order = data.map((_, index) => index).reverse().sort((a, b) => (b === this.emphasized) - (a === this.emphasized))
      order.forEach(index => {
        if (this.compact && index !== this.emphasized) return
        if (this.emphasized !== null && index !== this.emphasized) return
        const point = chart.getDatasetMeta(index).data.at(-1)
        if (!point || taken.some(other => Math.abs(other.y - point.y) < 14 && Math.abs(other.x - point.x) < 60)) return
        taken.push({ x: point.x, y: point.y })
        const text = this.shortDate(data[index]), width = ctx.measureText(text).width
        const flip = point.x + 9 + width > chart.width
        ctx.textAlign = flip ? "right" : "left"
        ctx.fillText(text, point.x + (flip ? -9 : 9), point.y - (flip ? 12 : 0))
      })
      ctx.restore()
    } }
  }

  // Phones get short dose-only markers so stacked labels don't dwarf the chart.
  get compact() { return this.trajectoryTarget.parentElement.clientWidth < 500 }
  get laneSize() { return this.compact ? { half: 27, height: 30 } : { half: 54, height: 62 } }
  calendarLanes(events, toPixel) {
    const occupied = []
    const { half } = this.laneSize
    return events.map(shot => {
      const x = toPixel(shot)
      let lane = occupied.findIndex(right => x - half > right + 6)
      if (lane < 0) lane = occupied.length
      occupied[lane] = x + half
      return { shot, x, lane }
    })
  }

  renderCalendar() {
    const history = this.payloadValue.history
    this.timelineTitleTarget.textContent = "Weight & injection dates"
    const data = history.raw, events = history.injections
    this.timelineExplanationTarget.textContent = "Tap a shot or a weight point for details."
    this.trajectoryCaptionTarget.textContent = ""
    this.trajectoryTarget.setAttribute("aria-label", "Weight history on actual calendar dates and weekdays, with labeled dose, location and date markers for actual injections. Exact measurements are available in day journals and shot details.")
    if (this.empty(this.trajectoryTarget, "No entries in these dates.", data.length > 0 || events.length > 0)) return
    const width = this.trajectoryTarget.parentElement.clientWidth
    const compact = this.compact, lane = this.laneSize
    const lanes = this.calendarLanes(events, shot => (shot.x - history.from) / (history.to - history.from) * Math.max(1, width - (compact ? 60 : 180)))
    const laneCount = Math.max(0, ...lanes.map(event => event.lane + 1))
    this.trajectoryTarget.parentElement.style.height = `${(compact ? 250 : 320) + laneCount * lane.height}px`
    const options = this.options()
    options.layout = { padding: { top: (compact ? 12 : 18) + laneCount * lane.height, left: compact ? 0 : 60, right: compact ? 14 : 60 } }
    options.parsing = false
    options.scales.x.type = "linear"
    options.scales.x.min = history.from
    options.scales.x.max = history.to
    options.scales.x.grid.display = false
    options.scales.x.ticks.maxTicksLimit = width < 500 ? 4 : 7
    options.scales.x.ticks.maxRotation = 0
    options.scales.x.ticks.font.size = width < 500 ? 9 : 11
    options.scales.x.ticks.callback = value => [new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, weekday: "short" }).format(value), new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, month: width < 500 && history.days?.length > 0 && history.days.length <= 14 ? "numeric" : "short", day: "numeric", ...(history.to - history.from > 366 * 86400000 ? { year: "numeric" } : {}) }).format(value)]
    options.scales.x.afterBuildTicks = scale => {
      if (!history.days?.length) return
      const limit = Math.max(1, Math.floor((width - 110) / (width < 500 ? 32 : 80)))
      const stride = Math.max(1, Math.ceil(history.days.length / limit))
      scale.ticks = history.days.filter((_, index) => index % stride === 0).map(day => ({ value: day.noon }))
    }
    options.scales.x.ticks.autoSkip = !history.days?.length
    options.scales.y.title = { display: data.length > 0 && !compact, text: `Actual weight (${this.payloadValue.unit})`, color: this.color("--muted") }
    if (compact) { options.scales.y.ticks.maxTicksLimit = 5; options.scales.y.ticks.font.size = 10 }
    options.scales.y.ticks.display = data.length > 0
    options.scales.y.grace = "12%"
    options.plugins.tooltip.callbacks = {
      title: items => items.length ? this.date(new Date(items[0].raw.x)) : "",
      label: item => `${item.raw.y.toFixed(2)} ${this.payloadValue.unit} · actual weigh-in`,
      afterBody: items => items.length ? events.filter(shot => shot.day === items[0].raw.day).map(shot => `${shot.dose} mg · ${shot.site} / ${shot.side} · ${this.date(shot.at)}`) : []
    }
    options.onClick = (_, elements) => { if (elements.length) globalThis.Turbo.visit(`/journal/${encodeURIComponent(data[elements[0].index].day)}`) }
    const guides = { id: "calendarInjectionGuides", beforeDatasetsDraw: chart => {
      const ctx = chart.ctx
      ctx.save(); ctx.setLineDash([4, 4]); ctx.lineWidth = 1.5
      events.forEach(shot => {
        const x = chart.scales.x.getPixelForValue(shot.x)
        ctx.strokeStyle = this.doseColor(shot.dose); ctx.beginPath(); ctx.moveTo(x, chart.chartArea.top); ctx.lineTo(x, chart.chartArea.bottom); ctx.stroke()
      })
      ctx.restore()
    } }
    const chart = new globalThis.Chart(this.trajectoryTarget, { type: "line", options, plugins: [guides], data: { datasets: [{ data, label: "Actual weight", cubicInterpolationMode: "monotone", tension: 0.35, spanGaps: false, borderColor: this.color("--chart-line"), backgroundColor: context => this.calendarGradient(context.chart), fill: "start", pointBackgroundColor: this.color("--chart-line"), pointRadius: compact && data.length > 40 ? 2.5 : 4, pointHitRadius: 14, pointBorderWidth: 1.5, pointBorderColor: this.color("--card") }] } })
    this.charts.push(chart)
    this.calendarLanes(events, shot => chart.scales.x.getPixelForValue(shot.x)).forEach(({ shot, x, lane }) => {
      const button = document.createElement("button")
      button.type = "button"; button.className = `injection-calendar-marker ${this.doseKey(shot.dose)}${compact ? " compact" : ""}`
      button.style.left = `${x}px`; button.style.top = `${(compact ? 6 : 12) + lane * this.laneSize.height}px`;
      for (const text of [`${shot.dose} mg`, `${shot.site} · ${shot.side}`, new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, weekday: "short", month: "short", day: "numeric" }).format(new Date(shot.at))]) { const span = document.createElement("span"); span.textContent = text; button.append(span) }
      button.title = this.date(shot.at); button.setAttribute("aria-label", `${shot.dose} mg · ${shot.site} / ${shot.side} · ${this.date(shot.at)}. Open shot details.`)
      button.addEventListener("click", () => this.openShot(shot.id)); this.calendarEventsTarget.append(button)
    })
  }

  calendarGradient(chart) {
    const color = this.color("--chart-line"), area = chart.chartArea
    if (!area) return `${color}22`
    const gradient = chart.ctx.createLinearGradient(0, area.top, 0, area.bottom)
    gradient.addColorStop(0, `${color}60`); gradient.addColorStop(0.65, `${color}20`); gradient.addColorStop(1, `${color}00`)
    return gradient
  }

  renderShots() {
    const data = this.payloadValue.shots
    this.shotWrapTarget.style.height = `${Math.max(260, data.length * 64 + 75)}px`
    if (this.empty(this.shotsTarget, "No measured change yet.", data.some(shot => shot.change !== null))) return
    const options = this.options()
    options.indexAxis = "y"
    options.scales.x.title = { display: true, text: `Measured change (${this.payloadValue.unit})`, color: this.color("--muted") }
    options.scales.x.beginAtZero = true
    options.scales.x.grace = "8%"
    options.scales.y.grid.display = false
    options.scales.y.ticks.font.size = 10
    options.scales.y.ticks.autoSkip = false
    options.plugins.tooltip.callbacks = {
      title: items => `Shot ${data[items[0].dataIndex].number} · ${data[items[0].dataIndex].day}`,
      label: item => {
        const shot = data[item.dataIndex]
        if (shot.change === null) return ["No measured pair yet", `${shot.dose} mg · ${shot.site} · ${shot.side}`]
        return [`${shot.dose} mg · ${shot.site} · ${shot.side}`, `${this.signed(shot.change)} ${this.payloadValue.unit} · ${this.percentage(shot.percent)}`, `${shot.span.toFixed(2)} days between readings${shot.status === "open" ? " · In progress" : ""}`]
      }
    }
    options.onClick = (_, elements) => { if (elements.length) this.openShot(data[elements[0].index].id) }
    const valueLabels = this.valueLabels("shotValueLabels", data, "No paired readings")
    this.shotsTarget.setAttribute("aria-label", "Observed weight change for each injection, labeled by date, dose, location and side. Each measured bar shows weight lost or gained; missing pairs remain unmeasured. Exact readings are in the shot cards below.")
    this.charts.push(new globalThis.Chart(this.shotsTarget, { type: "bar", options, plugins: [valueLabels],
      data: { labels: data.map(shot => [`#${shot.number} · ${new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, month: "short", day: "numeric" }).format(new Date(shot.at))} · ${shot.dose} mg`, `${shot.site} · ${shot.side}`]),
        datasets: [{ data: data.map(shot => shot.change), borderWidth: 1, borderRadius: 4,
          borderColor: data.map(shot => this.doseColor(shot.dose)),
          backgroundColor: data.map(shot => this.doseColor(shot.dose) + (shot.status === "open" ? "55" : "bb")) }] }
    }))
  }

  renderComparison(canvas, wrapper, groups, sites) {
    wrapper.style.height = `${Math.max(210, groups.length * 50 + 65)}px`
    if (this.empty(canvas, "Needs weigh-ins before and after a shot.", groups.some(group => group.change !== null))) return
    const options = this.options()
    options.indexAxis = "y"
    options.scales.y.grid.display = false
    options.scales.y.ticks.font.size = 10
    options.scales.x.beginAtZero = true
    options.scales.x.title = { display: true, text: `Total measured change (${this.payloadValue.unit})`, color: this.color("--muted") }
    options.plugins.tooltip.callbacks = { label: item => {
      const group = groups[item.dataIndex]
      if (group.change === null) return ["No measured shot yet", `${group.shots} logged shots`]
      return [`Total: ${this.signed(group.change)} ${this.payloadValue.unit} · ${this.percentage(group.percent)}`, `Average per shot: ${this.signed(group.average)} ${this.payloadValue.unit}`, `${group.measured} of ${group.shots} shots measured${group.in_progress ? ` · ${group.in_progress} in progress` : ""}`]
    } }
    options.scales.x.grace = "8%"
    const valueLabels = this.valueLabels(`${sites ? "site" : "dose"}ValueLabels`, groups, "No completed pair")
    this.charts.push(new globalThis.Chart(canvas, { type: "bar", options, plugins: [valueLabels],
      data: { labels: groups.map(group => group.label), datasets: [{ data: groups.map(group => group.change), borderRadius: 4,
        backgroundColor: groups.map(group => (sites ? this.siteColor(group.label.split(" · ")[0]) : this.doseColor(parseFloat(group.label))) + "bb") }] }
    }))
  }

  // Writes "1.2 lb lost" and its percentage on (or beside) each horizontal bar.
  valueLabels(id, items, emptyLabel) {
    return { id, afterDatasetsDraw: chart => {
      const ctx = chart.ctx, area = chart.chartArea
      ctx.save(); ctx.textBaseline = "middle"
      items.forEach((item, index) => {
        ctx.font = "600 11px system-ui"
        const bar = chart.getDatasetMeta(0).data[index]
        const y = chart.scales.y.getPixelForValue(index)
        const label = item.change === null ? emptyLabel : `${Math.abs(item.change).toFixed(1)} ${this.payloadValue.unit}${item.change < 0 ? " lost" : item.change > 0 ? " gained" : " change"}`
        const percentage = item.change === null || item.percent === null || item.percent === undefined ? null : this.percentage(item.percent)
        const width = Math.max(ctx.measureText(label).width, percentage ? ctx.measureText(percentage).width : 0) + 12
        const length = item.change === null ? 0 : Math.abs(bar.x - bar.base)
        let x = item.change === null ? area.left + width / 2 + 4 : length >= width ? (bar.x + bar.base) / 2 : bar.x + (item.change < 0 ? -1 : 1) * (width / 2 + 4)
        x = Math.max(area.left + width / 2, Math.min(area.right - width / 2, x))
        ctx.fillStyle = this.color("--card"); ctx.globalAlpha = 0.94
        ctx.beginPath(); ctx.roundRect(x - width / 2, y - (percentage ? 18 : 11), width, percentage ? 36 : 22, 4); ctx.fill(); ctx.globalAlpha = 1
        ctx.fillStyle = this.color(item.change === null ? "--muted" : "--ink"); ctx.textAlign = "center"; ctx.fillText(label, x, y - (percentage ? 6 : 0))
        if (percentage) { ctx.font = "10px system-ui"; ctx.fillText(percentage, x, y + 8) }
      })
      ctx.restore()
    } }
  }

  signed(value, digits = 2) { return `${value > 0 ? "+" : value < 0 ? "−" : ""}${Math.abs(value).toFixed(digits)}` }
  shortDate(shot) { return new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, month: "short", day: "numeric" }).format(new Date(shot.at)) }
  percentage(value) { return value === null || value === undefined ? "Percentage unavailable" : `${Math.abs(value).toFixed(1)}% ${value < 0 ? "lost" : value > 0 ? "gained" : "change"}` }
  customDates() { this.rangeTarget.value = "custom" }
  date(value) { return new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, weekday: "short", year: "numeric", month: "short", day: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short" }).format(new Date(value)) }
  openShot(id) {
    const card = document.getElementById(`shot-${id}`)
    if (!card) return
    card.open = true
    card.scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "center" })
    card.focus({ preventScroll: true })
  }
}
