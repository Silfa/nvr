from fastapi import APIRouter
import shutil
import subprocess
import os
import logging
from typing import Any
from common import config_loader

router = APIRouter()
logger = logging.getLogger(__name__)

from common.config_loader import RECORDS_DIR_BASE

# Removed local get_config_value

@router.get("/status")
async def get_system_status():
    """
    Get system status (disk usage, service status).
    """
    # Disk Usage (NVR Storage)
    storage_path = RECORDS_DIR_BASE

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
