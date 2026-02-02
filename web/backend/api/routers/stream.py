from fastapi import APIRouter, Response
from fastapi.responses import StreamingResponse
from typing import Any
import subprocess
import os
import logging
from common import config_loader

router = APIRouter()
logger = logging.getLogger(__name__)

NVR_CONFIG_DIR = os.getenv("NVR_CONFIG_DIR", "/etc/nvr")
MAIN_CONFIG = config_loader.load_main_config()

def get_config_value(key_path: str) -> Any:
     keys = key_path.split('.')
     val = MAIN_CONFIG
     for k in keys:
         if isinstance(val, dict):
             val = val.get(k)
         else:
             return None
     return val

def get_records_dir_base() -> str:
    val = get_config_value("common.records_dir_base")
    if val:
        return val
    logger.warning("Using fallback records path: /mnt/WD_Purple/NVR/records")
    return "/mnt/WD_Purple/NVR/records"

@router.get("/live/{camera_name}")
async def stream_live(camera_name: str):
    return {"message": "Live streaming via HLS/DASH planned for future development. Use Dashboard for low-fps preview."}

@router.get("/playback/{camera_name}/{filename}")
async def stream_recording(camera_name: str, filename: str, ss: float = 0):
    """
    Stream a specific MKV file as MP4 (fragmented) on the fly.
    """
    records_base = get_records_dir_base()
    file_path = os.path.join(records_base, camera_name, filename)
    
    if not os.path.exists(file_path):
        logger.warning(f"File not found: {file_path}")
        return Response(status_code=404)

    # Load camera config to check type
    camera_config_path = os.path.join(NVR_CONFIG_DIR, "cameras", f"{camera_name}.yaml")
    is_esp32cam = False
    
    # Try to determine if this is an ESP32-CAM (which often has broken timestamps requiring forced FPS)
    try:
        cam_config = config_loader.load_camera_config(camera_name)
        if cam_config.get("type") == "esp32cam":
            is_esp32cam = True
    except Exception as e:
        logger.debug(f"Could not load camera config for {camera_name}: {e}")

    # FFmpeg command to remux MKV to fragmented MP4
    ffmpeg_cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning"]
    
    # For ESP32-CAM, we use a simple -r 5 to prevent extreme fast-forward,
    # but we skip stretching and seeking as they are inaccurate due to non-linear frame drops.
    if is_esp32cam:
        ffmpeg_cmd.extend(["-r", "5", "-i", file_path])
        # Note: 'ss' is ignored here as requested by the user.
    else:
        if ss > 0:
            ffmpeg_cmd.extend(["-ss", str(ss)])
        ffmpeg_cmd.extend(["-i", file_path])

    ffmpeg_cmd.extend([
        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-tune", "zerolatency",
        "-an", # Drop audio for now
        "-movflags", "frag_keyframe+empty_moov+default_base_moof",
        "-f", "mp4",
        "pipe:1"
    ])
    
    async def iter_file():
        process = subprocess.Popen(
            ffmpeg_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=1024*1024
        )
        
        try:
            while True:
                chunk = process.stdout.read(128 * 1024)
                if not chunk:
                    if process.poll() is not None and process.returncode != 0:
                        err = process.stderr.read().decode()
                        logger.error(f"FFmpeg error: {err}")
                    break
                yield chunk
        except Exception as e:
            logger.error(f"Streaming generator error: {e}")
            process.kill()
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait()

    return StreamingResponse(
        iter_file(), 
        media_type="video/mp4",
        headers={
            "Accept-Ranges": "bytes",
            "Content-Type": "video/mp4"
        }
    )
