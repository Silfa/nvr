import os
import subprocess
import functools
import logging
from datetime import datetime
from typing import Optional

logger = logging.getLogger(__name__)

def parse_recording_timestamp(filename: str) -> Optional[datetime]:
    """
    Parse the start timestamp from a recording filename (YYYYMMDD_HHMMSS.mkv).
    """
    try:
        basename = os.path.basename(filename)
        name = os.path.splitext(basename)[0]
        return datetime.strptime(name, "%Y%m%d_%H%M%S")
    except Exception:
        return None

@functools.lru_cache(maxsize=1024)
def get_video_duration(file_path: str) -> float:
    """
    Get the actual media duration of a video file using ffprobe.
    """
    try:
        cmd = [
            "ffprobe", "-v", "error", 
            "-show_entries", "format=duration", 
            "-of", "default=noprint_wrappers=1:nokey=1", 
            file_path
        ]
        output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode().strip()
        try:
            return float(output)
        except ValueError:
            lines = output.splitlines()
            if lines:
                return float(lines[0])
            return 0.0
    except Exception as e:
        logger.error(f"Failed to get duration for {file_path}: {e}")
        return 0.0
