func makeApp(_ spec: AppSpec) -> PocketApp? {
    if let site = spec.web { return WebApp(spec: spec, site: site) }
    switch spec.id {
    case "calendar": return CalendarApp(spec: spec)
    case "todo": return TodoApp(spec: spec)
    case "pomodoro": return PomodoroApp(spec: spec)
    case "calculator": return CalculatorApp(spec: spec)
    default: return nil
    }
}
