import uvicorn
import logging
from common import config_loader

# Setup Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("nvr.web.runner")

def load_config():
    main_cfg = config_loader.load_main_config()
    
    defaults = {"port": 8000, "host": "0.0.0.0"}
    
    return {
        "port": config_loader.get_config_value(main_cfg, "common.web.port", defaults["port"]),
        "host": config_loader.get_config_value(main_cfg, "common.web.host", defaults["host"])
    }

if __name__ == "__main__":
    config = load_config()
    host = config["host"]
    port = config["port"]
    
    logger.info(f"Starting Web API server at {host}:{port}")
    
    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        reload=False,
        log_level="info"
    )
