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
    // The web frontend receives only a local model:// URL. It never gets arbitrary
    // filesystem access; the protocol below still verifies the requested extension/path.
    let normalized_path = path.to_string_lossy().replace('\\', "/");
    let model_url = format!("model://localhost/{}", urlencoding::encode(&normalized_path));
    let file_name = path.file_name().and_then(|name| name.to_str()).unwrap_or("model");

    format!(
        "index.html?open={}&name={}",
        urlencoding::encode(&model_url),
        urlencoding::encode(file_name)
    )
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
                // Lets Online3DViewer's own HTML5 drop handler receive Explorer drops.
                .disable_drag_drop_handler()
                .build()?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running O3D Viewer");
}
