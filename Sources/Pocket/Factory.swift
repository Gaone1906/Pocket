func makeApp(_ spec: AppSpec) -> PocketApp? {
    if let site = spec.web {
        if spec.id == "matinee" { return MatineeApp(spec: spec, site: site) }
        return WebApp(spec: spec, site: site)
    }
    if let link = spec.link { return LinkApp(spec: spec, url: link) }
    switch spec.id {
    case "calendar": return CalendarApp(spec: spec)
    case "todo": return TodoApp(spec: spec)
    case "pomodoro": return PomodoroApp(spec: spec)
    case "schedule": return ScheduleApp(spec: spec)
    case "runner": return KairosApp(spec: spec)
    case "calculator": return CalculatorApp(spec: spec)
    case "stats": return StatsApp(spec: spec)
    case "scratchpad": return ScratchpadApp(spec: spec)
    default: return nil
    }
}
