//! Scaffolding for Forge's Rust core. Deliberately holds no git/search/
//! diff logic yet — Phase 1 of Forge ships entirely against the GitHub
//! REST API from Swift. This crate's only job right now is to prove the
//! Rust<->Swift bridge (toolchain, cross-compile, XCFramework packaging,
//! UniFFI bindings) actually works end-to-end, so later phases have a
//! working seam to build real functionality on instead of starting cold.

uniffi::setup_scaffolding!();

mod repo;
pub use repo::*;

/// The one real call Swift makes into this crate right now — surfaced in
/// `ForgeDashboardView`'s footer so the bridge being real (not assumed) is
/// visible in the running app, not just proven in a build log.
#[uniffi::export]
pub fn engine_status() -> String {
    format!("forge-core v{} online", env!("CARGO_PKG_VERSION"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn engine_status_reports_online() {
        assert!(engine_status().contains("online"));
    }
}
