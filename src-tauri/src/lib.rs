mod commands;

pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![commands::runtime_info])
        .run(tauri::generate_context!())
        .expect("failed to run Den");
}
