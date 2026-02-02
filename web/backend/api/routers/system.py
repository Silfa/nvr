from fastapi import APIRouter
import shutil
import subprocess
import os
import logging
from typing import Any
from common import config_loader

router = APIRouter()
logger = logging.getLogger(__name__)

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

@router.get("/status")
async def get_system_status():
    """
    Get system status (disk usage, service status).
    """
    # Disk Usage (NVR Storage)
    storage_path = get_config_value("common.records_dir_base")
    if not storage_path:
         # Fallback but log warning
         logger.warning("Using fallback storage path: /mnt/WD_Purple/NVR")
         storage_path = "/mnt/WD_Purple/NVR"

    try:
        total, used, free = shutil.disk_usage(storage_path)
    except Exception as e:
        # Fallback if path doesn't exist
        logger.error(f"Failed to check disk usage for {storage_path}: {e}")
        total, used, free = 0, 0, 0

    disk_info = {
        "total_gb": total // (2**30) if total > 0 else 0,
        "used_gb": used // (2**30) if used > 0 else 0,
        "free_gb": free // (2**30) if free > 0 else 0,
        "percent": (used / total) * 100 if total > 0 else 0
    }

    # Service Status (mock for now, or use systemctl)
    services = {
        "nvr": "active", # Placeholder
    }

    return {
        "disk": disk_info,
        "services": services
    }
