from fastapi import APIRouter, Response
from fastapi.responses import StreamingResponse
from typing import Any
import subprocess
import os
import logging
from common import config_loader

router = APIRouter()
logger = logging.getLogger(__name__)

from common.config_loader import RECORDS_DIR_BASE, NVR_CONFIG_DIR, load_camera_config

# Removed redundant get_records_dir_base and helper functions

@router.get("/live/{camera_name}")
async def stream_live(camera_name: str):
    return {"message": "Live streaming via HLS/DASH planned for future development. Use Dashboard for low-fps preview."}

@router.get("/playback/{camera_name}/{filename}")
async def stream_recording(camera_name: str, filename: str, ss: float = 0):
    """
    Stream a specific MKV file as MP4 (fragmented) on the fly.
    """
    file_path = os.path.join(RECORDS_DIR_BASE, camera_name, filename)
    
    if not os.path.exists(file_path):
        logger.warning(f"File not found: {file_path}")
        return Response(status_code=404)

    # Load camera config to check type
    camera_config_path = os.path.join(NVR_CONFIG_DIR, "cameras", f"{camera_name}.yaml")
    is_esp32cam = False
    
    # Try to determine if this is an ESP32-CAM (which often has broken timestamps requiring forced FPS)
    try:
        cam_config = load_camera_config(camera_name)
        if cam_config.get("type") == "esp32cam":
            is_esp32cam = True
    except Exception as e:
        logger.debug(f"Could not load camera config for {camera_name}: {e}")

    # FFmpeg command to remux MKV to fragmented MP4
    ffmpeg_cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning"]
    
    # For ESP32-CAM, we use a simple copy (-c:v copy) to be as lightweight as possible.
    if is_esp32cam:
        # User requested seeking functionality but with a small margin (start early).
        # We apply -ss if offset is meaningful.
        if ss > 0:
            # Shift back by 5 seconds for safety, but not before the start of the file.
            effective_ss = max(0, ss - 5)
            ffmpeg_cmd.extend(["-ss", str(effective_ss)])
            
        ffmpeg_cmd.extend(["-i", file_path, "-c:v", "copy"])
    else:
        if ss > 0:
            ffmpeg_cmd.extend(["-ss", str(ss)])
        ffmpeg_cmd.extend(["-i", file_path, "-c:v", "libx264", "-preset", "ultrafast", "-tune", "zerolatency"])

    ffmpeg_cmd.extend([
        "-an", # Drop audio for now
        "-movflags", "frag_keyframe+empty_moov+default_base_moof",
        "-f", "mp4",
        "pipe:1"
    ])
    
    async def iter_file():
        import asyncio
        process = await asyncio.create_subprocess_exec(
            *ffmpeg_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        try:
            while True:
                # Read from stdout
                chunk = await process.stdout.read(128 * 1024)
                if not chunk:
                    break
                yield chunk
        except Exception as e:
            logger.error(f"Streaming generator error: {e}")
        finally:
            if process.returncode is None:
                try:
                    process.kill()
                    await process.wait()
                except ProcessLookupError:
                    pass
            logger.debug(f"FFmpeg process {process.pid} cleaned up.")

    return StreamingResponse(
        iter_file(), 
        media_type="video/mp4",
        headers={
            "Accept-Ranges": "bytes",
            "Content-Type": "video/mp4"
        }
    )
