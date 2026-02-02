import yaml
import os

# root所有のファイルを読み取る
with open("/etc/nvr/install_paths", "r") as f:
    _paths = yaml.safe_load(f)

# 定数として定義
NVR_USER = _paths['user']
NVR_BASE_DIR = _paths['base_dir']
NVR_CORE_DIR = _paths['core_dir']
NVR_COMMON_DIR = _paths['common_dir']
NVR_LIB_DIR = _paths['lib_dir']
NVR_CONFIG_MAIN_FILE = _paths['config_main_file']
NVR_CONFIG_MAIN_SECRET_FILE = _paths['config_main_secret_file']
NVR_CONFIG_CAM_DIR = _paths['config_cam_dir']
NVR_CONFIG_CAM_SECRET_DIR = _paths['config_cam_secret_dir']
# NVR_CONFIG_DIR is usually /etc/nvr
_config_dir = os.path.dirname(NVR_CONFIG_MAIN_FILE)
NVR_CONFIG_MASK_DIR = os.path.join(_config_dir, "masks")
# Override if specified in paths
if 'config_mask_dir' in _paths:
    NVR_CONFIG_MASK_DIR = _paths['config_mask_dir']

def load_main_config():
    config = {}
    if os.path.exists(NVR_CONFIG_MAIN_FILE):
        with open(NVR_CONFIG_MAIN_FILE, "r") as f:
            config = yaml.safe_load(f) or {}

    if os.path.exists(NVR_CONFIG_MAIN_SECRET_FILE):
        with open(NVR_CONFIG_MAIN_SECRET_FILE, "r") as f:
            secrets = yaml.safe_load(f) or {}
            _deep_update(config, secrets)
    return config

def load_camera_config(cam):
    public_path = os.path.join(NVR_CONFIG_CAM_DIR,f"{cam}.yaml")
    secret_path = os.path.join(NVR_CONFIG_CAM_SECRET_DIR,f"{cam}.yaml")

    with open(public_path, "r") as f:
        config = yaml.safe_load(f) or {}
        
    if os.path.exists(secret_path):
        with open(secret_path, "r") as f:
            secrets = yaml.safe_load(f) or {}
            _deep_update(config, secrets)
    return config

def _deep_update(base, src):
    for k, v in src.items():
        if isinstance(v, dict) and k in base and isinstance(base[k], dict):
            _deep_update(base[k], v)
        else:
            base[k] = v

def get_config_value(config, key_path, default=None):
    """
    Get a value from a nested dictionary using a dot-separated key path.
    """
    keys = key_path.split('.')
    val = config
    for k in keys:
        if isinstance(val, dict):
            val = val.get(k)
        else:
            return default
    return val if val is not None else default