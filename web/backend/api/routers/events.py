from fastapi import APIRouter, Response, Query
from fastapi.responses import FileResponse
import os
import glob
import shutil
import json
import logging
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
import bisect
import functools
import subprocess

from common import config_loader
from common.video_utils import parse_recording_timestamp, get_video_duration

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

def get_events_dir_base() -> str:
    val = get_config_value("common.events_dir_base")
    if val:
        return val
    logger.warning("Using fallback events path: /mnt/WD_Purple/NVR/events")
    return "/mnt/WD_Purple/NVR/events"

def get_records_dir_base() -> str:
    val = get_config_value("common.records_dir_base")
    if val:
        return val
    logger.warning("Using fallback records path: /mnt/WD_Purple/NVR/records")
    return "/mnt/WD_Purple/NVR/records"


def find_video_for_event(camera: str, event_time: datetime) -> tuple[Optional[str], int]:
    records_base = get_records_dir_base()
    cam_records_dir = os.path.join(records_base, camera)
    
    if not os.path.exists(cam_records_dir):
        logger.warning(f"Records dir not found: {cam_records_dir}")
        return None, 0

    # Get all record files
    files = sorted(glob.glob(os.path.join(cam_records_dir, "*.mkv")))
    if not files:
        logger.warning(f"No recordings found in {cam_records_dir}")
        return None, 0
    
    # Extract timestamps
    timestamps = []
    valid_files = []
    for f in files:
        ts = parse_recording_timestamp(f)
        if ts:
            timestamps.append(ts)
            valid_files.append(f)
            
    if not timestamps:
        logger.warning(f"No valid timestamps parsed in {cam_records_dir}")
        return None, 0

    # Ensure event_time is naive for comparison if file timestamps are naive
    # Assumption: Filenames are in local time, stored as naive by strptime.
    if event_time.tzinfo is not None:
        event_time = event_time.replace(tzinfo=None)

    # Find the latest recording strictly before or equal to event_time
    # bisect_right returns insertion point after the timestamp.
    # index-1 is the candidate.
    idx = bisect.bisect_right(timestamps, event_time)
    
    if idx == 0:
        logger.warning(f"Event time {event_time} is before all recordings. First rec: {timestamps[0]}")
        return None, 0 # All recordings are newer than event
        
    candidate_idx = idx - 1
    candidate_file = valid_files[candidate_idx]
    candidate_ts = timestamps[candidate_idx]
    
    # Calculate offset
    offset = (event_time - candidate_ts).total_seconds()
    
    # Check if the event is actually within the file duration (plus some safety margin)
    # 1. First check wall-clock duration via mtime (fast)
    try:
        mtime = os.path.getmtime(candidate_file)
        file_end_ts_naive = datetime.fromtimestamp(mtime).replace(tzinfo=None)
        
        # Give a small safety margin (e.g. 5 seconds) to account for write delays
        if event_time > (file_end_ts_naive + timedelta(seconds=5)):
             logger.warning(f"Event {event_time} is after candidate file wall-clock end {file_end_ts_naive} (gap detected)")
             return None, 0
             
        # 2. Check actual media duration (involves ffprobe)
        media_duration = get_video_duration(candidate_file)
        if media_duration > 0:
            # If offset exceeds media duration, we still allow it if it's within the wall-clock window (mtime).
            # This handles cases where frames are dropped due to network instability (ESP32-CAM).
            # stream.py will handle this by forcing the framerate during playback.
            if offset > media_duration:
                logger.info(f"Event {event_time} offset {offset} exceeds media duration {media_duration} for {candidate_file}, but is within wall-clock window. Allowing.")
            
    except Exception as e:
        logger.error(f"Error checking file duration for {candidate_file}: {e}")
    
    logger.info(f"Found video {os.path.basename(candidate_file)} for event {event_time} with offset {offset}")
    return os.path.basename(candidate_file), int(max(0, offset))


@router.get("/")
async def list_events(
    camera: Optional[str] = None,
    date: Optional[str] = None, # YYYYMMDD or YYYY-MM-DD
    start_time: Optional[str] = None, # HHMMSS or HH:MM:SS
    end_time: Optional[str] = None,   # HHMMSS or HH:MM:SS
    limit: int = 60
):
    base_dir = get_events_dir_base()
    events_list = []
    
    # To optimize, we traverse carefully.
    # Structure: base_dir/camera/YYYY/MM/event_id/event.json
    
    # Filter cameras
    cameras_to_scan = [camera] if camera else [d for d in os.listdir(base_dir) if os.path.isdir(os.path.join(base_dir, d))]
    
    for cam in cameras_to_scan:
        cam_dir = os.path.join(base_dir, cam)
        if not os.path.exists(cam_dir):
            continue
            
        # Year
        years = sorted([y for y in os.listdir(cam_dir) if y.isdigit()], reverse=True)
        
        for year in years:
            year_dir = os.path.join(cam_dir, year)
            
            # Month
            months = sorted([m for m in os.listdir(year_dir) if m.isdigit()], reverse=True)
            
            for month in months:
                month_dir = os.path.join(year_dir, month)
                
                # Event IDs (which act as directories)
                # event_id is like YYYYMMDD_HHMMSS
                event_ids = sorted([e for e in os.listdir(month_dir) if os.path.isdir(os.path.join(month_dir, e))], reverse=True)
                
                for eid in event_ids:
                    # Check limit
                    if len(events_list) >= limit:
                        break
                        
                    # Date Filtering (Optimize by skipping based on event_id prefix)
                    # event_id format: YYYYMMDD_HHMMSS
                    if len(eid) >= 15:
                        ev_date_str = eid[:8] # YYYYMMDD
                        ev_time_str = eid[9:15] # HHMMSS
                        
                        if date:
                            search_date = date.replace("-", "")
                            if ev_date_str != search_date:
                                continue
                                
                        if start_time and end_time:
                            st = start_time.replace(":", "")
                            et = end_time.replace(":", "")
                            # Basic string compare for HHMMSS works
                            if not (st <= ev_time_str <= et):
                                continue

                    # Load event.json
                    json_path = os.path.join(month_dir, eid, "event.json")
                    if os.path.exists(json_path):
                        try:
                            with open(json_path, "r") as f:
                                meta = json.load(f)
                                
                            # Enrich with derived data
                            meta["event_id"] = eid
                            meta["year"] = year
                            meta["month"] = month
                            
                            # Calculate Video File and Offset
                            if "timestamp" in meta:
                                try:
                                    ts = datetime.fromisoformat(meta["timestamp"])
                                    vfile, offset = find_video_for_event(meta["camera"], ts)
                                    meta["video_file"] = vfile
                                    meta["start_offset"] = offset
                                except Exception:
                                    meta["video_file"] = None
                                    meta["start_offset"] = 0
                            
                            events_list.append(meta)
                        except Exception as e:
                            logger.error(f"Error loading {json_path}: {e}")
                            
                if len(events_list) >= limit:
                    break
            if len(events_list) >= limit:
                break
        if len(events_list) >= limit:
            break
            
    return events_list

@router.delete("/{camera}/{year}/{month}/{event_id}")
async def delete_event(camera: str, year: str, month: str, event_id: str):
    base_dir = get_events_dir_base()
    event_dir = os.path.join(base_dir, camera, year, month, event_id)
    
    if os.path.exists(event_dir):
        try:
            shutil.rmtree(event_dir)
            return {"message": f"Event {event_id} deleted"}
        except Exception as e:
            return {"error": str(e)}
    return Response(status_code=404)

@router.get("/{camera}/{year}/{month}/{event_id}/frames")
async def list_event_frames(camera: str, year: str, month: str, event_id: str):
    base_dir = get_events_dir_base()
    event_dir = os.path.join(base_dir, camera, year, month, event_id)
    
    if not os.path.exists(event_dir):
        return []
        
    # List .jpg files
    frames = sorted([f for f in os.listdir(event_dir) if f.lower().endswith(".jpg")])
    return frames

@router.get("/{camera}/{year}/{month}/{event_id}/thumbnail")
async def get_event_thumbnail(camera: str, year: str, month: str, event_id: str):
    base_dir = get_events_dir_base()
    event_dir = os.path.join(base_dir, camera, year, month, event_id)
    
    # Try 0001.jpg, or finding any jpg
    thumb_path = os.path.join(event_dir, "0001.jpg")
    if not os.path.exists(thumb_path):
        frames = sorted(glob.glob(os.path.join(event_dir, "*.jpg")))
        if frames:
            thumb_path = frames[0]
        else:
            return Response(status_code=404)
            
    return FileResponse(thumb_path, media_type="image/jpeg")

@router.get("/{camera}/{year}/{month}/{event_id}/frame/{frame}")
async def get_event_frame(camera: str, year: str, month: str, event_id: str, frame: str):
    base_dir = get_events_dir_base()
    frame_path = os.path.join(base_dir, camera, year, month, event_id, frame)
    
    if not os.path.exists(frame_path):
        return Response(status_code=404)
            
    return FileResponse(frame_path, media_type="image/jpeg")
