use std::{env, fs, path::{Path, PathBuf}};

use http::{header, Response, StatusCode};
use tauri::{WebviewUrl, WebviewWindowBuilder};

const SUPPORTED_EXTENSIONS: &[&str] = &[
    "3dm", "3ds", "3mf", "amf", "bim", "brep", "dae", "fcstd", "fbx", "gltf", "glb",
    "ifc", "iges", "igs", "step", "stp", "stl", "obj", "off", "ply", "wrl"
];

fn is_supported_model(path: &Path) -> bool {
    path.is_file()
        && path
            .extension()
            .and_then(|ext| ext.to_str())
            .map(|ext| SUPPORTED_EXTENSIONS.iter().any(|known| ext.eq_ignore_ascii_case(known)))
            .unwrap_or(false)
}

fn model_path_from_arguments() -> Option<PathBuf> {
    env::args_os()
        .skip(1)
        .map(PathBuf::from)
        .find(|path| is_supported_model(path))
}

fn app_url_for_model(path: &Path) -> String {
    // The model is delivered through our read-only `model://` protocol. The path is encoded twice:
    // once for the custom protocol URL and once as the query value of the Tauri app URL.
    let normalized_path = path.to_string_lossy().replace('\\', "/");
    let model_url = format!("model://localhost/{}", urlencoding::encode(&normalized_path));
    format!("index.html?open={}", urlencoding::encode(&model_url))
}

fn error_response(status: StatusCode, message: &str) -> Response<Vec<u8>> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, "text/plain; charset=utf-8")
        .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
        .body(message.as_bytes().to_vec())
        .expect("valid error response")
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let model_path = model_path_from_arguments();
    let app_url = match model_path.as_deref() {
        Some(path) => app_url_for_model(path),
        None => "index.html".to_string(),
    };

    tauri::Builder::default()
        .register_uri_scheme_protocol("model", |_ctx, request| {
            // The URL is always generated locally by this application. It intentionally exposes
            // only the one model path encoded in the startup URL, not a general file browser API.
            let encoded = request.uri().path().trim_start_matches('/');
            let decoded = match urlencoding::decode(encoded) {
                Ok(path) => path.into_owned(),
                Err(_) => return error_response(StatusCode::BAD_REQUEST, "Invalid model path."),
            };

            let path = PathBuf::from(decoded);
            if !is_supported_model(&path) {
                return error_response(StatusCode::NOT_FOUND, "Model file was not found or is unsupported.");
            }

            match fs::read(&path) {
                Ok(data) => Response::builder()
                    .status(StatusCode::OK)
                    .header(header::CONTENT_TYPE, "application/octet-stream")
                    .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
                    .header(header::ACCESS_CONTROL_ALLOW_METHODS, "GET, OPTIONS")
                    .body(data)
                    .expect("valid model response"),
                Err(_) => error_response(StatusCode::NOT_FOUND, "Could not read the selected model file."),
            }
        })
        .setup(move |app| {
            WebviewWindowBuilder::new(app, "main", WebviewUrl::App(app_url.into()))
                .title("O3D Viewer")
                .inner_size(1440.0, 900.0)
                .min_inner_size(960.0, 640.0)
                .resizable(true)
                // Required on Windows so Online3DViewer's own HTML5 drag-and-drop handler receives files.
                .disable_drag_drop_handler()
                .build()?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running O3D Viewer");
}
