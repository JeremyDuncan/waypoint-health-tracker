import { Controller } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["range", "trajectory", "trajectoryCaption", "timelineMode", "timelineTitle", "timelineExplanation", "calendarEvents", "shots", "shotWrap", "sites", "siteWrap", "doses", "doseWrap"]
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

  renderTrajectories() {
    this.calendarEventsTarget.replaceChildren()
    if (this.timelineModeTarget.value === "calendar") return this.renderCalendar()
    this.trajectoryTarget.parentElement.style.height = ""
    this.timelineTitleTarget.textContent = "Compare weight changes after shots"
    this.timelineExplanationTarget.textContent = "Each line compares a different shot’s measured weight change. All injection dates are aligned to day 0; the horizontal axis is elapsed days, not calendar weekdays."
    this.trajectoryTarget.setAttribute("aria-label", "Comparison of measured weight changes with each injection aligned to day zero. This view overlays different calendar weeks. Actual dates appear in tooltips and shot details.")
    const data = this.payloadValue.trajectories
    this.trajectoryCaptionTarget.textContent = data.length
      ? `Latest ${data.length} paired shots from different weeks. Day 0 is each shot’s own injection, not one shared date. The baseline keeps its actual timing; later points are measured follow-ups. Tap a point for its shot details.`
      : "A nearby baseline and at least one later weigh-in are needed for a trajectory. No missing readings are estimated."
    if (this.empty(this.trajectoryTarget, "Your measured trajectories will appear here once a shot has a baseline and follow-up.", data.length > 0)) return
    const options = this.options()
    const allPoints = data.flatMap(shot => shot.points)
    options.scales.x.type = "linear"
    options.scales.x.min = Math.min(-3, ...allPoints.map(point => point.x))
    options.scales.x.max = Math.max(7, ...allPoints.map(point => point.x))
    options.scales.x.title = { display: true, text: "Days since each shot (0 = its injection)", color: this.color("--muted") }
    options.scales.x.ticks.stepSize = 1
    options.scales.x.ticks.maxTicksLimit = 7
    options.scales.y.title = { display: true, text: `Change from baseline (${this.payloadValue.unit})`, color: this.color("--muted") }
    options.scales.y.grace = "15%"
    options.plugins.tooltip.callbacks = {
      title: items => {
        const shot = data[items[0].datasetIndex]
        return `Shot ${shot.number} · ${shot.day} · ${shot.dose} mg`
      },
      label: item => {
        const shot = data[item.datasetIndex]
        return [`${shot.site} · ${shot.side}`, `${this.signed(item.raw.y)} ${this.payloadValue.unit} from baseline`, `Measured: ${item.raw.value.toFixed(2)} ${this.payloadValue.unit}`, this.date(item.raw.at)]
      }
    }
    options.onClick = (_, elements) => { if (elements.length) this.openShot(data[elements[0].datasetIndex].id) }
    const reference = { id: "injectionReference", beforeDatasetsDraw: chart => {
      const x = chart.scales.x.getPixelForValue(0)
      const ctx = chart.ctx
      ctx.save(); ctx.strokeStyle = this.color("--injection-border"); ctx.setLineDash([4, 4]); ctx.lineWidth = 1.5
      ctx.beginPath(); ctx.moveTo(x, chart.chartArea.top); ctx.lineTo(x, chart.chartArea.bottom); ctx.stroke()
      ctx.setLineDash([]); ctx.fillStyle = this.color("--muted"); ctx.font = "11px system-ui"; ctx.textAlign = "center"
      ctx.fillText("All shots aligned to day 0", x, chart.chartArea.top - 7); ctx.restore()
    } }
    options.layout = { padding: { top: 18, right: 12 } }
    this.charts.push(new globalThis.Chart(this.trajectoryTarget, {
      type: "line", options, plugins: [reference],
      data: { datasets: data.map(shot => ({ label: `Shot ${shot.number}`, data: shot.points, parsing: false,
        borderColor: this.siteColor(shot.site), backgroundColor: this.siteColor(shot.site),
        borderWidth: 2, pointRadius: 3, pointHitRadius: 12, pointHoverRadius: 6,
        pointBorderColor: this.color("--card"), pointBorderWidth: 1.5, cubicInterpolationMode: "monotone", tension: 0.35, spanGaps: false,
        borderDash: shot.status === "open" ? [5, 4] : [] })) }
    }))
  }

  calendarLanes(events, toPixel) {
    const occupied = []
    return events.map(shot => {
      const x = toPixel(shot)
      let lane = occupied.findIndex(right => x - 54 > right + 6)
      if (lane < 0) lane = occupied.length
      occupied[lane] = x + 54
      return { shot, x, lane }
    })
  }

  renderCalendar() {
    const history = this.payloadValue.history
    this.timelineTitleTarget.textContent = "Weight & injection dates"
    const data = history.raw, events = history.injections
    this.timelineExplanationTarget.textContent = "Actual calendar dates and weekdays. The green line shows recorded weight; labeled guides mark the shots you logged. Tap a shot label for its details, or a weight point for that day’s journal."
    this.trajectoryCaptionTarget.textContent = `All ${data.length} readings in the selected dates, with ${events.length} matching shots. Location and dose filters apply to shot markers. Curves are visual connectors; no injection is assigned a weight measurement.`
    this.trajectoryTarget.setAttribute("aria-label", "Weight history on actual calendar dates and weekdays, with labeled dose, location and date markers for actual injections. Exact measurements are available in day journals and shot details.")
    if (this.empty(this.trajectoryTarget, "No weight readings or actual injections in these dates.", data.length > 0 || events.length > 0)) return
    const width = this.trajectoryTarget.parentElement.clientWidth
    const lanes = this.calendarLanes(events, shot => (shot.x - history.from) / (history.to - history.from) * Math.max(1, width - 180))
    const laneCount = Math.max(0, ...lanes.map(event => event.lane + 1))
    this.trajectoryTarget.parentElement.style.height = `${320 + laneCount * 62}px`
    const options = this.options()
    options.layout = { padding: { top: 18 + laneCount * 62, left: 60, right: 60 } }
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
    options.scales.y.title = { display: data.length > 0, text: `Actual weight (${this.payloadValue.unit})`, color: this.color("--muted") }
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
        ctx.strokeStyle = this.siteColor(shot.site); ctx.beginPath(); ctx.moveTo(x, chart.chartArea.top); ctx.lineTo(x, chart.chartArea.bottom); ctx.stroke()
      })
      ctx.restore()
    } }
    const chart = new globalThis.Chart(this.trajectoryTarget, { type: "line", options, plugins: [guides], data: { datasets: [{ data, label: "Actual weight", cubicInterpolationMode: "monotone", tension: 0.35, spanGaps: false, borderColor: this.color("--chart-line"), backgroundColor: context => this.calendarGradient(context.chart), fill: "start", pointBackgroundColor: this.color("--chart-line"), pointRadius: 4, pointHitRadius: 14, pointBorderWidth: 1.5, pointBorderColor: this.color("--card") }] } })
    this.charts.push(chart)
    this.calendarLanes(events, shot => chart.scales.x.getPixelForValue(shot.x)).forEach(({ shot, x, lane }) => {
      const button = document.createElement("button")
      button.type = "button"; button.className = "injection-calendar-marker"
      button.style.left = `${x}px`; button.style.top = `${12 + lane * 62}px`; button.style.borderColor = this.siteColor(shot.site)
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
    if (this.empty(this.shotsTarget, "No measured change yet. Expand a shot below to see which reading is missing.", data.some(shot => shot.change !== null))) return
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
    const valueLabels = { id: "shotValueLabels", afterDatasetsDraw: chart => {
      const ctx = chart.ctx, area = chart.chartArea
      ctx.save(); ctx.font = "600 11px system-ui"; ctx.textBaseline = "middle"
      data.forEach((shot, index) => {
        ctx.font = "600 11px system-ui"
        const bar = chart.getDatasetMeta(0).data[index]
        const y = chart.scales.y.getPixelForValue(index)
        const label = shot.change === null ? "No paired readings" : `${Math.abs(shot.change).toFixed(1)} ${this.payloadValue.unit}${shot.change < 0 ? " lost" : shot.change > 0 ? " gained" : " change"}`
        const percentage = shot.percent === null ? null : this.percentage(shot.percent)
        const width = Math.max(ctx.measureText(label).width, percentage ? ctx.measureText(percentage).width : 0) + 12
        const length = shot.change === null ? 0 : Math.abs(bar.x - bar.base)
        let x = shot.change === null ? area.left + width / 2 + 4 : length >= width ? (bar.x + bar.base) / 2 : bar.x + (shot.change < 0 ? -1 : 1) * (width / 2 + 4)
        x = Math.max(area.left + width / 2, Math.min(area.right - width / 2, x))
        ctx.fillStyle = this.color("--card"); ctx.globalAlpha = 0.94
        ctx.beginPath(); ctx.roundRect(x - width / 2, y - (percentage ? 18 : 11), width, percentage ? 36 : 22, 4); ctx.fill(); ctx.globalAlpha = 1
        ctx.fillStyle = this.color(shot.change === null ? "--muted" : "--ink"); ctx.textAlign = "center"; ctx.fillText(label, x, y - (percentage ? 6 : 0))
        if (percentage) { ctx.font = "10px system-ui"; ctx.fillText(percentage, x, y + 8) }
      })
      ctx.restore()
    } }
    this.shotsTarget.setAttribute("aria-label", "Observed weight change for each injection, labeled by date, dose, location and side. Each measured bar shows weight lost or gained; missing pairs remain unmeasured. Exact readings are in the shot cards below.")
    this.charts.push(new globalThis.Chart(this.shotsTarget, { type: "bar", options, plugins: [valueLabels],
      data: { labels: data.map(shot => [`#${shot.number} · ${new Intl.DateTimeFormat("en-US", { timeZone: this.payloadValue.zone, month: "short", day: "numeric" }).format(new Date(shot.at))} · ${shot.dose} mg`, `${shot.site} · ${shot.side}`]),
        datasets: [{ data: data.map(shot => shot.change), borderWidth: 1, borderRadius: 4,
          borderColor: data.map(shot => this.siteColor(shot.site)),
          backgroundColor: data.map(shot => this.siteColor(shot.site) + (shot.status === "open" ? "55" : "bb")) }] }
    }))
  }

  renderComparison(canvas, wrapper, groups, sites) {
    wrapper.style.height = `${Math.max(210, groups.length * 43 + 65)}px`
    if (this.empty(canvas, "Completed windows with paired weigh-ins at least 24 hours apart are needed for this comparison.", groups.some(group => group.change !== null))) return
    const options = this.options()
    options.indexAxis = "y"
    options.scales.y.grid.display = false
    options.scales.y.ticks.font.size = 10
    options.scales.x.beginAtZero = true
    options.scales.x.title = { display: true, text: `Mean measured change (${this.payloadValue.unit})`, color: this.color("--muted") }
    options.plugins.tooltip.callbacks = { label: item => {
      const group = groups[item.dataIndex]
      if (group.change === null) return ["No completed measurement pair", `${group.shots} logged shots`]
      return [`${this.signed(group.change)} ${this.payloadValue.unit}`, `${group.compared} compared of ${group.shots} logged shots`, `${group.span.toFixed(1)} days between readings on average`]
    } }
    this.charts.push(new globalThis.Chart(canvas, { type: "bar", options,
      data: { labels: groups.map(group => group.label), datasets: [{ data: groups.map(group => group.change), borderRadius: 4,
        backgroundColor: groups.map(group => (sites ? this.siteColor(group.label.split(" · ")[0]) : this.color("--chart-line")) + "bb") }] }
    }))
  }

  signed(value) { return `${value > 0 ? "+" : ""}${value.toFixed(2)}` }
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
