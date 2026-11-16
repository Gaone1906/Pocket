func makeApp(_ spec: AppSpec) -> PocketApp? {
    if let site = spec.web { return WebApp(spec: spec, site: site) }
    return nil
}
