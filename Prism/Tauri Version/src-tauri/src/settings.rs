use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use uuid::Uuid;

fn default_conversation_model() -> String {
    "flash".to_string()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub api_key: String,
    /// Stable installation-scoped identifier for DeepSeek usage/KVCache
    /// isolation. It contains no account, device, or conversation data.
    #[serde(default)]
    pub user_id: String,
    pub base_url: String,
    pub flash_model: String,
    pub pro_model: String,
    /// Model family used for normal conversation turns. Keep Flash as the
    /// factory default; the concrete model identifiers remain editable below.
    #[serde(default = "default_conversation_model")]
    pub conversation_model: String,
    pub language: String,
    pub default_mode: String,
    pub response_length: String,
    pub summary_interval: i32,
    pub context_window: i32,
    pub pro_thinking_enabled: bool,
    pub pro_reasoning_effort: String,
    pub flash_thinking_enabled: bool,
    pub flash_reasoning_effort: String,
    #[serde(alias = "iCloudSync")]
    pub icloud_sync: bool,
    pub data_path: String,
    pub onboarding_completed: bool,
    pub enable_logging: bool,
    /// Schema marker for preference migrations. Older settings files do not
    /// contain this field and are treated as version 0 on read.
    #[serde(default)]
    pub model_defaults_version: u8,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            api_key: String::new(),
            user_id: Self::load_or_create_user_id(),
            base_url: "https://api.deepseek.com".to_string(),
            flash_model: "deepseek-v4-flash-vision-exp".to_string(),
            pro_model: "deepseek-v4-pro".to_string(),
            conversation_model: default_conversation_model(),
            language: "en".to_string(),
            default_mode: "balanced".to_string(),
            response_length: "standard".to_string(),
            summary_interval: 5,
            context_window: 60,
            pro_thinking_enabled: true,
            // V4 Flash is the default conversation model. DeepSeek documents
            // thinking=enabled and reasoning_effort=high as the regular
            // request defaults, so both model families start there.
            pro_reasoning_effort: "high".to_string(),
            flash_thinking_enabled: true,
            flash_reasoning_effort: "high".to_string(),
            icloud_sync: false,
            data_path: Self::default_data_path(),
            onboarding_completed: false,
            enable_logging: true,
            model_defaults_version: 4,
        }
    }
}

impl Settings {
    fn is_valid_user_id(user_id: &str) -> bool {
        !user_id.is_empty()
            && user_id.len() <= 512
            && user_id.chars().all(|character| {
                character.is_ascii_alphanumeric() || character == '-' || character == '_'
            })
    }

    fn installation_id_path() -> PathBuf {
        Self::bootstrap_path()
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .join("installation_id")
    }

    fn persist_user_id(user_id: &str) {
        let path = Self::installation_id_path();
        if let Some(parent) = path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(path, user_id);
    }

    fn load_or_create_user_id() -> String {
        let path = Self::installation_id_path();
        if let Ok(saved) = std::fs::read_to_string(path) {
            let saved = saved.trim();
            if Self::is_valid_user_id(saved) {
                return saved.to_string();
            }
        }

        let user_id = format!("prism_tauri_{}", Uuid::new_v4());
        Self::persist_user_id(&user_id);
        user_id
    }

    pub fn ensure_user_id(&mut self) -> bool {
        if Self::is_valid_user_id(&self.user_id) {
            Self::persist_user_id(&self.user_id);
            return false;
        }
        self.user_id = Self::load_or_create_user_id();
        true
    }

    /// Resolve the current user's home directory on every desktop platform.
    ///
    /// Windows applications are not guaranteed to have `HOME` set (the
    /// canonical variable there is `USERPROFILE`), while development shells
    /// such as Git Bash often set both. Prefer the native Windows variable so
    /// Prism does not accidentally write into a Unix-like compatibility path.
    fn home_dir() -> PathBuf {
        if cfg!(target_os = "windows") {
            if let Ok(user_profile) = std::env::var("USERPROFILE") {
                if !user_profile.trim().is_empty() {
                    return PathBuf::from(user_profile);
                }
            }
            if let (Ok(drive), Ok(path)) = (std::env::var("HOMEDRIVE"), std::env::var("HOMEPATH")) {
                let combined = format!("{}{}", drive, path);
                if !combined.trim().is_empty() {
                    return PathBuf::from(combined);
                }
            }
        }

        if let Ok(home) = std::env::var("HOME") {
            if !home.trim().is_empty() {
                return PathBuf::from(home);
            }
        }

        // This is only a last-resort fallback for unusual sandboxes. Make it
        // absolute so normalize_data_path never persists a relative path.
        std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
    }

    fn documents_dir() -> PathBuf {
        Self::home_dir().join("Documents")
    }

    /// The first-run location used when no user-selected storage location has
    /// been saved yet. This remains stable across launches and upgrades.
    pub fn default_data_path() -> String {
        Self::documents_dir()
            .join("Prism")
            .to_string_lossy()
            .to_string()
    }

    /// Local iCloud Drive path used by the macOS Swift implementation too.
    /// This is the on-disk iCloud Drive mirror, not an arbitrary placeholder;
    /// files placed here are picked up by iCloud Drive when it is available.
    pub fn icloud_data_path() -> Option<PathBuf> {
        if !cfg!(target_os = "macos") {
            return None;
        }
        let home = std::env::var("HOME").ok()?;
        let drive_root = PathBuf::from(home).join("Library/Mobile Documents/com~apple~CloudDocs");
        if drive_root.is_dir() {
            Some(drive_root.join("Documents/Prism"))
        } else {
            None
        }
    }

    /// A tiny, independent pointer that tells the next launch where the real
    /// settings file lives. The settings file itself is intentionally stored
    /// in the user-selected data directory, so the pointer cannot live there.
    pub fn bootstrap_path() -> PathBuf {
        let base = if cfg!(target_os = "windows") {
            std::env::var_os("APPDATA")
                .filter(|path| !path.is_empty())
                .map(PathBuf::from)
                .unwrap_or_else(|| Self::home_dir().join("AppData/Roaming"))
        } else if cfg!(target_os = "macos") {
            Self::home_dir().join("Library/Application Support")
        } else if let Some(config_home) = std::env::var_os("XDG_CONFIG_HOME") {
            PathBuf::from(config_home)
        } else {
            Self::home_dir().join(".config")
        };
        base.join("Prism/storage_path")
    }

    pub fn normalize_data_path(&mut self) {
        // The onboarding UI may not yet have a selected folder. Never persist
        // an empty path (or the human-readable iCloud label) as a relative
        // directory; use Prism's known local default in that case.
        if self.data_path.trim().is_empty() || !std::path::Path::new(&self.data_path).is_absolute()
        {
            self.data_path = Self::default().data_path;
        }
    }

    /// Upgrade earlier factory presets so the default conversation model uses
    /// DeepSeek V4 Flash Vision Exp while preserving custom model choices.
    fn migrate_model_defaults(&mut self) -> bool {
        if self.model_defaults_version >= 4 {
            return false;
        }

        if self.model_defaults_version < 2
            && self.flash_model == "deepseek-v4-flash"
            && !self.flash_thinking_enabled
            && self.flash_reasoning_effort == "high"
        {
            self.flash_thinking_enabled = true;
            self.flash_reasoning_effort = "max".to_string();
        }
        if self.model_defaults_version < 2
            && self.pro_model == "deepseek-v4-pro"
            && self.pro_thinking_enabled
            && self.pro_reasoning_effort == "high"
        {
            self.pro_reasoning_effort = "max".to_string();
        }
        if self.flash_model == "deepseek-v4-flash" && self.flash_reasoning_effort == "max" {
            self.flash_reasoning_effort = "high".to_string();
        }
        if self.pro_model == "deepseek-v4-pro" && self.pro_reasoning_effort == "max" {
            self.pro_reasoning_effort = "high".to_string();
        }
        // V4 Flash Vision Exp is the new default conversation model. Preserve
        // custom provider choices and migrate only the previous factory value.
        if self.flash_model == "deepseek-v4-flash" {
            self.flash_model = "deepseek-v4-flash-vision-exp".to_string();
        }
        self.model_defaults_version = 4;
        true
    }

    pub fn data_dir(&self) -> PathBuf {
        PathBuf::from(&self.data_path).join("Data")
    }

    pub fn settings_path(&self) -> PathBuf {
        PathBuf::from(&self.data_path).join("settings.json")
    }

    pub fn conversations_path(&self) -> PathBuf {
        PathBuf::from(&self.data_path).join("conversations.json")
    }

    pub fn load() -> Self {
        let default = Self::default();

        // Prefer the bootstrap pointer. A previous version wrote settings
        // directly into the selected directory, so reading only the default
        // path made every custom-location install look like a fresh setup.
        let bootstrap = Self::bootstrap_path();
        if let Ok(selected_root) = std::fs::read_to_string(&bootstrap) {
            let selected_root = selected_root.trim();
            if !selected_root.is_empty() {
                if let Some(settings) =
                    Self::read_from_path(Path::new(selected_root).join("settings.json"))
                {
                    return settings;
                }
            }
        }

        // Keep compatibility with installations created before the pointer
        // existed. If that file contains a custom absolute path, migrate the
        // pointer on the next save (and opportunistically now).
        if let Some(settings) = Self::read_from_path(default.settings_path()) {
            if settings.onboarding_completed && settings.data_path != default.data_path {
                let _ = Self::write_bootstrap(&settings.data_path);
            }
            return settings;
        }

        // One-time migration for pre-pointer Tauri builds. Those builds put
        // settings.json directly in the selected folder, so there is no
        // global index to consult. Limit discovery to immediate Documents
        // children and require the stored dataPath to exactly match the
        // candidate folder; this avoids treating unrelated JSON as Prism
        // settings while preserving the common Prism/Prism-* layout.
        if let Some(settings) = Self::find_legacy_documents_settings(&default) {
            let _ = Self::write_bootstrap(&settings.data_path);
            return settings;
        }

        // Swift stores its configuration as config.json. Import that format
        // as a final compatibility fallback so conversations can move between
        // the two implementations without forcing a new setup.
        if let Some(settings) = Self::find_legacy_documents_config(&default) {
            let _ = Self::write_bootstrap(&settings.data_path);
            return settings;
        }

        default
    }

    pub fn save(&self) -> Result<(), String> {
        let path = self.settings_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Cannot create settings directory: {}", e))?;
        }
        let data = serde_json::to_string_pretty(self)
            .map_err(|e| format!("Cannot encode settings: {}", e))?;
        std::fs::write(&path, data).map_err(|e| format!("Cannot save settings: {}", e))?;

        // Keep this outside the selected data directory so changing folders
        // cannot strand the app on the next launch.
        Self::write_bootstrap(&self.data_path)
    }

    fn read_from_path(path: PathBuf) -> Option<Self> {
        let data = std::fs::read_to_string(&path).ok()?;
        let mut settings = serde_json::from_str::<Self>(&data).ok()?;
        settings.normalize_data_path();
        let migrated = settings.migrate_model_defaults();
        let identity_added = settings.ensure_user_id();
        if migrated || identity_added {
            // Persist the migration at the same location so a user who
            // intentionally changes these controls later is not re-migrated.
            if let Ok(encoded) = serde_json::to_string_pretty(&settings) {
                let _ = std::fs::write(&path, encoded);
            }
        }
        Some(settings)
    }

    fn read_swift_config(path: PathBuf, data_path: String) -> Option<Self> {
        let data = std::fs::read_to_string(path).ok()?;
        let value: serde_json::Value = serde_json::from_str(&data).ok()?;
        let mut settings = Self::default();
        settings.api_key = value["apiKey"].as_str().unwrap_or("").to_string();
        settings.base_url = value["baseURL"]
            .as_str()
            .or_else(|| value["baseUrl"].as_str())
            .unwrap_or(&settings.base_url)
            .to_string();
        settings.pro_model = value["model"]
            .as_str()
            .unwrap_or(&settings.pro_model)
            .to_string();
        settings.flash_model = value["flashModel"]
            .as_str()
            .unwrap_or(&settings.flash_model)
            .to_string();
        settings.conversation_model = value["conversationModel"]
            .as_str()
            .or_else(|| value["chatModel"].as_str())
            .unwrap_or(&settings.conversation_model)
            .to_string();
        settings.language = match value["language"].as_str().unwrap_or("en") {
            "zh-Hans" | "zh-CN" => "zh".to_string(),
            "zh-Hant" | "zh-TW" | "zh-HK" => "zh-hant".to_string(),
            language => language.to_string(),
        };
        settings.summary_interval = value["summaryDialogCount"]
            .as_i64()
            .unwrap_or(settings.summary_interval as i64) as i32;
        settings.default_mode = value["conversationMode"]
            .as_str()
            .unwrap_or(&settings.default_mode)
            .to_string();
        settings.response_length = value["responseLength"]
            .as_str()
            .unwrap_or(&settings.response_length)
            .to_string();
        settings.onboarding_completed = value["onboardingCompleted"].as_bool().unwrap_or(false);
        settings.icloud_sync = value["useiCloud"].as_bool().unwrap_or(false);
        settings.pro_thinking_enabled = value["parameters"]["thinkingEnabled"]
            .as_bool()
            .unwrap_or(settings.pro_thinking_enabled);
        settings.pro_reasoning_effort = value["parameters"]["reasoningEffort"]
            .as_str()
            .unwrap_or(&settings.pro_reasoning_effort)
            .to_string();
        settings.flash_thinking_enabled = value["flashParameters"]["thinkingEnabled"]
            .as_bool()
            .unwrap_or(settings.flash_thinking_enabled);
        settings.flash_reasoning_effort = value["flashParameters"]["reasoningEffort"]
            .as_str()
            .unwrap_or(&settings.flash_reasoning_effort)
            .to_string();
        settings.data_path = data_path;
        Some(settings)
    }

    fn write_bootstrap(data_path: &str) -> Result<(), String> {
        let path = Self::bootstrap_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Cannot create Prism bootstrap directory: {}", e))?;
        }
        std::fs::write(&path, data_path.trim())
            .map_err(|e| format!("Cannot save Prism storage pointer: {}", e))
    }

    fn find_legacy_documents_settings(default: &Settings) -> Option<Self> {
        let documents = Self::documents_dir();
        let mut candidates: Vec<(SystemTime, Self)> = Vec::new();

        for entry in std::fs::read_dir(documents).ok()? {
            let Ok(entry) = entry else { continue };
            let root = entry.path();
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if root == Path::new(&default.data_path) || !file_type.is_dir() {
                continue;
            }

            let settings_path = root.join("settings.json");
            let Some(settings) = Self::read_from_path(settings_path.clone()) else {
                continue;
            };
            if !settings.onboarding_completed || Path::new(&settings.data_path) != root {
                continue;
            }

            let modified = std::fs::metadata(settings_path)
                .and_then(|metadata| metadata.modified())
                .unwrap_or(SystemTime::UNIX_EPOCH);
            candidates.push((modified, settings));
        }

        candidates
            .into_iter()
            .max_by_key(|(modified, _)| *modified)
            .map(|(_, settings)| settings)
    }

    fn find_legacy_documents_config(_default: &Settings) -> Option<Self> {
        let documents = Self::documents_dir();
        let mut candidates: Vec<(SystemTime, Self)> = Vec::new();

        for entry in std::fs::read_dir(documents).ok()? {
            let Ok(entry) = entry else { continue };
            let root = entry.path();
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if !file_type.is_dir() {
                continue;
            }
            let config_path = root.join("config.json");
            let Some(settings) =
                Self::read_swift_config(config_path.clone(), root.to_string_lossy().to_string())
            else {
                continue;
            };
            if !settings.onboarding_completed {
                continue;
            }
            let modified = std::fs::metadata(config_path)
                .and_then(|metadata| metadata.modified())
                .unwrap_or(SystemTime::UNIX_EPOCH);
            candidates.push((modified, settings));
        }

        candidates
            .into_iter()
            .max_by_key(|(modified, _)| *modified)
            .map(|(_, settings)| settings)
    }
}
