import { useState, useEffect } from 'react';

interface CameraPreviewProps {
    cameraName: string;
    refreshInterval?: number;
}

export function CameraPreview({ cameraName, refreshInterval = 1000 }: CameraPreviewProps) {
    const [timestamp, setTimestamp] = useState(Date.now());
    const [error, setError] = useState(false);

    useEffect(() => {
        const timer = setInterval(() => {
            setTimestamp(Date.now());
            setError(false);
        }, refreshInterval);

        return () => clearInterval(timer);
    }, [refreshInterval, cameraName]);

    const imageUrl = `/nvr/api/cameras/${cameraName}/latest?t=${timestamp}`;

    return (
        <div className="relative aspect-video bg-black rounded-lg overflow-hidden group border border-gray-700">
            {error ? (
                <div className="absolute inset-0 flex items-center justify-center text-gray-500 bg-gray-900">
                    Image not available
                </div>
            ) : (
                <img
                    src={imageUrl}
                    alt={`Live view of ${cameraName}`}
                    className="w-full h-full object-contain"
                    onError={() => setError(true)}
                />
            )}
            <div className="absolute top-2 left-2 bg-black/50 px-2 py-1 rounded text-xs text-white backdrop-blur-sm">
                {cameraName}
            </div>
            <div className="absolute bottom-2 right-2 flex items-center space-x-1">
                <div className="w-2 h-2 bg-red-500 rounded-full animate-pulse"></div>
                <span className="text-[10px] text-white/70 uppercase font-mono">Live</span>
            </div>
        </div>
    );
}
