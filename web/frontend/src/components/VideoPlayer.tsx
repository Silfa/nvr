import { useRef, useEffect, useState } from 'react';

interface VideoPlayerProps {
    cameraName: string;
    filename: string;
    startOffset?: number;
    onClose?: () => void;
}

export function VideoPlayer({ cameraName, filename, startOffset = 0, onClose }: VideoPlayerProps) {
    const videoRef = useRef<HTMLVideoElement>(null);
    const [playTime, setPlayTime] = useState(0);

    // URL to the streaming endpoint with optional start offset
    const videoUrl = `/nvr/api/stream/playback/${cameraName}/${filename}${startOffset > 0 ? `?ss=${startOffset}` : ''}`;

    // Parse start time from filename (YYYYMMDD_HHMMSS.mkv)
    const getStartTime = () => {
        const match = filename.match(/^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})/);
        if (!match) return null;
        const [_, y, m, d, hh, mm, ss] = match;
        return new Date(parseInt(y), parseInt(m) - 1, parseInt(d), parseInt(hh), parseInt(mm), parseInt(ss));
    };

    const startTime = getStartTime();

    const formatTimecode = (seconds: number) => {
        if (!startTime) return "";
        const current = new Date(startTime.getTime() + (seconds + startOffset) * 1000);
        return current.toLocaleString('ja-JP', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hour12: false
        });
    };

    useEffect(() => {
        if (videoRef.current) {
            videoRef.current.play().catch(err => {
                console.warn("Autoplay failed:", err);
            });
        }
    }, [videoUrl]);

    return (
        <div className="flex flex-col h-full">
            <div className="flex items-center justify-between p-4 border-b border-gray-700">
                <h3 className="text-lg font-medium text-gray-200">
                    Playback: {filename}
                </h3>
                {onClose && (
                    <button
                        onClick={onClose}
                        className="text-gray-400 hover:text-white transition-colors"
                    >
                        <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                        </svg>
                    </button>
                )}
            </div>
            <div className="flex-1 bg-black flex items-center justify-center overflow-hidden relative">
                <video
                    ref={videoRef}
                    controls
                    className="max-w-full max-h-full"
                    src={videoUrl}
                    onTimeUpdate={(e) => setPlayTime(e.currentTarget.currentTime)}
                >
                    Your browser does not support the video tag.
                </video>

                {/* Timecode Overlay */}
                {startTime && (
                    <div className="absolute top-4 left-4 bg-black/60 backdrop-blur px-3 py-1.5 rounded-lg border border-white/10 text-white font-mono text-sm shadow-xl pointer-events-none">
                        <div className="flex items-center space-x-2">
                            <div className="w-2 h-2 bg-red-500 rounded-full animate-pulse"></div>
                            <span>{formatTimecode(playTime)}</span>
                        </div>
                    </div>
                )}
            </div>
            <div className="p-4 text-xs text-gray-500 bg-gray-900/50">
                Camera: <span className="text-gray-300">{cameraName}</span> |
                Format: <span className="text-gray-300">MKV (Remuxed to MP4)</span>
            </div>
        </div>
    );
}
