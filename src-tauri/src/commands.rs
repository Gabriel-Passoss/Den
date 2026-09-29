use serde::Serialize;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RuntimeInfo {
    app_name: &'static str,
    app_version: &'static str,
    platform: &'static str,
    architecture: &'static str,
    ipc_version: u32,
}

#[tauri::command]
pub fn runtime_info() -> RuntimeInfo {
    RuntimeInfo {
        app_name: "Den",
        app_version: env!("CARGO_PKG_VERSION"),
        platform: std::env::consts::OS,
        architecture: std::env::consts::ARCH,
        ipc_version: 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn runtime_response_matches_the_frontend_contract() {
        let response = serde_json::to_value(runtime_info()).unwrap();
        assert_eq!(
            response,
            serde_json::json!({
                "appName": "Den",
                "appVersion": env!("CARGO_PKG_VERSION"),
                "platform": std::env::consts::OS,
                "architecture": std::env::consts::ARCH,
                "ipcVersion": 1
            })
        );
    }
}
