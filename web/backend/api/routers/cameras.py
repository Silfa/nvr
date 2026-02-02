from fastapi import APIRouter, Response, UploadFile, File
from fastapi.responses import FileResponse
import yaml
import os
import glob
import subprocess
import shutil
from common import config_loader

router = APIRouter()

MAIN_CONFIG = config_loader.load_main_config()

def get_camera_status(camera_name: str) -> str:
    """
    Check if the camera's ffmpeg service is active.
    """
    try:
        cmd = ["systemctl", "is-active", f"ffmpeg_nvr@{camera_name}.service"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.stdout.strip()
    except Exception:
        return "unknown"

def get_motion_tmp_base() -> str:
    """
    Get motion_tmp_base from main.yaml.
    """
    return config_loader.get_config_value(MAIN_CONFIG, "common.motion_tmp_base", "/dev/shm/motion_tmp")

@router.get("/")
async def get_cameras():
    """
    List all cameras from cameras.yaml files with active status.
    """
    cameras = []
    cam_files = glob.glob(os.path.join(config_loader.NVR_CONFIG_CAM_DIR, "*.yaml"))
    
    for f in cam_files:
        try:
            cam_name = os.path.splitext(os.path.basename(f))[0]
            data = config_loader.load_camera_config(cam_name)
            if data:
                # Handle both single camera file and multi-camera structure if any
                # Usually, backend splits them. Let's assume standard format.
                name = data.get("name")
                if name:
                    data["status"] = get_camera_status(name)
                    cameras.append(data)
        except Exception as e:
            print(f"Error reading {f}: {e}")
            
    return cameras

@router.get("/{camera_name}")
async def get_camera_config(camera_name: str):
    """
    Get specific camera configuration including status.
    """
    try:
        data = config_loader.load_camera_config(camera_name)
        if not data:
             return {"error": "Camera not found or empty configuration"}
        data["status"] = get_camera_status(camera_name)
        return data
    except Exception as e:
        return {"error": str(e)}

@router.get("/{camera_name}/latest")
async def get_camera_latest(camera_name: str):
    """
    Serve the latest.jpg image for the camera.
    """
    tmp_base = get_motion_tmp_base()
    img_path = os.path.join(tmp_base, camera_name, "latest.jpg")
    
    if not os.path.exists(img_path):
        return Response(status_code=404)
        
    return FileResponse(img_path, media_type="image/jpeg")

@router.post("/{camera_name}/config")
async def update_camera_config(camera_name: str, config: dict):
    """
    Update specific camera configuration.
    Note: In a real system, we should validate the schema.
    """
    file_path = os.path.join(config_loader.NVR_CONFIG_CAM_DIR, f"{camera_name}.yaml")
    if not os.path.exists(file_path):
        return {"error": "Camera not found"}
        
    try:
        # NOTE: load_camera_config merges secrets. For editing, we might want to edit only public?
        # But the original code was loading from file_path directly.
        # Here we follow the original logic of loading/merging/dumping back to the same PUBLIC file.
        with open(file_path, "r") as stream:
            data = yaml.safe_load(stream) or {}
            
        if "motion" in config:
            data["motion"] = config["motion"]
        if "daynight" in config:
            data["daynight"] = config["daynight"]
        if "connection" in config:
            data["connection"] = config["connection"]

        with open(file_path, "w") as stream:
            yaml.safe_dump(data, stream, default_flow_style=False)
            
        # Optional: trigger service restart if needed? 
        # For motion detector, it needs a restart to pick up new values.
        # Hardcore way: subprocess.run(["sudo", "systemctl", "restart", f"motion_detector@{camera_name}"])
        
        return {"message": "Configuration updated successfully"}
    except Exception as e:
        return {"error": str(e)}

@router.post("/{camera_name}/restart")
async def restart_camera_services(camera_name: str):
    """
    Restart services related to a specific camera.
    """
    services = [
        f"ffmpeg_nvr@{camera_name}.service",
        f"motion_detector@{camera_name}.service",
        f"motion_event_handler@{camera_name}.service"
    ]
    
    results = {}
    for svc in services:
        try:
            # We use sudo because systemctl restart requires privileges.
            cmd = ["sudo", "systemctl", "restart", svc]
            subprocess.run(cmd, check=True, capture_output=True)
            results[svc] = "restarted"
        except subprocess.CalledProcessError as e:
            results[svc] = f"failed: {e.stderr.decode().strip()}"
        except Exception as e:
            results[svc] = f"error: {str(e)}"
            
    return results

@router.get("/{camera_name}/mask")
async def get_camera_mask(camera_name: str):
    """
    Check if a mask image exists for the camera and return it.
    """
    file_path = os.path.join(NVR_CONFIG_DIR, "masks", f"{camera_name}.png")
    if not os.path.exists(file_path):
        return Response(status_code=404)
        
    return FileResponse(file_path, media_type="image/png")

@router.post("/{camera_name}/mask")
async def upload_camera_mask(camera_name: str, file: UploadFile = File(...)):
    """
    Upload a grayscale mask image (PNG recommended) for the camera.
    Saved to /etc/nvr/masks/<camera_name>.png
    """
    mask_dir = os.path.join(NVR_CONFIG_DIR, "masks")
    os.makedirs(mask_dir, exist_ok=True)
    
    file_path = os.path.join(mask_dir, f"{camera_name}.png")
    
    try:
        with open(file_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)
        return {"message": f"Mask uploaded for {camera_name}"}
    except Exception as e:
        return {"error": str(e)}
