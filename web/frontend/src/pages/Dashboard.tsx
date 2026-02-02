import { useEffect, useState } from 'react';
import { Layout } from '../layouts/Layout';
import { CameraPreview } from '../components/CameraPreview';

interface Camera {
    name: string;
    enabled: boolean;
    status: string;
    [key: string]: any;
}

interface SystemStatus {
    disk: {
        total_gb: number;
        used_gb: number;
        free_gb: number;
        percent: number;
    };
    services: Record<string, string>;
}

export function Dashboard() {
    const [status, setStatus] = useState<SystemStatus | null>(null);
    const [cameras, setCameras] = useState<Camera[]>([]);
    const [selectedCamera, setSelectedCamera] = useState<string | null>(null);

    useEffect(() => {
        const fetchData = () => {
            // Fetch system status
            fetch('/nvr/api/system/status')
                .then(res => res.json())
                .then(data => setStatus(data))
                .catch(err => console.error("Failed to fetch status", err));

            // Fetch cameras
            fetch('/nvr/api/cameras/')
                .then(res => res.json())
                .then(data => {
                    setCameras(data);
                    // Set initial camera if none selected
                    if (data.length > 0 && !selectedCamera) {
                        setSelectedCamera(data[0].name);
                    }
                })
                .catch(err => console.error("Failed to fetch cameras", err));
        };

        fetchData();
        const interval = setInterval(fetchData, 5000); // Refresh every 5s

        return () => clearInterval(interval);
    }, [selectedCamera]);

    return (
        <Layout>
            <div className="grid grid-cols-1 lg:grid-cols-4 gap-6">
                {/* Left Column: List & Stats */}
                <div className="lg:col-span-1 space-y-6">
                    {/* System Status Card */}
                    <div className="bg-gray-800 rounded-xl p-6 border border-gray-700 shadow-sm">
                        <h2 className="text-lg font-semibold mb-4 text-gray-200">System</h2>
                        {status ? (
                            <div className="space-y-4">
                                <div>
                                    <div className="flex justify-between text-sm mb-1">
                                        <span>Disk</span>
                                        <span>{status.disk.percent.toFixed(1)}%</span>
                                    </div>
                                    <div className="w-full bg-gray-700 rounded-full h-1.5">
                                        <div
                                            className="bg-blue-500 h-1.5 rounded-full"
                                            style={{ width: `${status.disk.percent}%` }}
                                        ></div>
                                    </div>
                                </div>
                                <div className="text-sm">
                                    <span className="text-gray-400">NVR API: </span>
                                    <span className="text-green-400 font-medium lowercase">active</span>
                                </div>
                            </div>
                        ) : (
                            <div className="animate-pulse space-y-3">
                                <div className="h-4 bg-gray-700 rounded w-3/4"></div>
                                <div className="h-2 bg-gray-700 rounded"></div>
                            </div>
                        )}
                    </div>

                    {/* Camera Selection Card */}
                    <div className="bg-gray-800 rounded-xl p-6 border border-gray-700 shadow-sm">
                        <h2 className="text-lg font-semibold mb-4 text-gray-200">Cameras</h2>
                        <div className="space-y-2">
                            {cameras.map(cam => (
                                <button
                                    key={cam.name}
                                    onClick={() => setSelectedCamera(cam.name)}
                                    className={`w-full text-left p-3 rounded-lg border transition-all flex items-center justify-between ${selectedCamera === cam.name
                                        ? 'bg-blue-600/20 border-blue-500 text-blue-100'
                                        : 'bg-gray-900/50 border-gray-700 text-gray-400 hover:border-gray-500'
                                        }`}
                                >
                                    <div className="flex items-center space-x-2">
                                        <span className={`w-2 h-2 rounded-full ${cam.status === 'active' ? 'bg-green-500' : 'bg-gray-600'}`}></span>
                                        <span className="font-medium">{cam.name}</span>
                                    </div>
                                    {cam.status !== 'active' && (
                                        <span className="text-[10px] uppercase font-mono bg-gray-700 px-1.5 py-0.5 rounded text-gray-400">offline</span>
                                    )}
                                </button>
                            ))}
                            {cameras.length === 0 && (
                                <div className="text-sm text-gray-500 italic">No cameras found.</div>
                            )}
                        </div>
                    </div>
                </div>

                {/* Right Column: Live View */}
                <div className="lg:col-span-3 space-y-6">
                    <div className="bg-gray-800 rounded-xl p-6 border border-gray-700 shadow-sm min-h-[400px]">
                        <div className="flex items-center justify-between mb-4">
                            <h2 className="text-lg font-semibold text-gray-200">Live Preview</h2>
                            {selectedCamera && (
                                <div className="text-sm text-gray-400 flex items-center space-x-2">
                                    <span>Camera: <b className="text-gray-200">{selectedCamera}</b></span>
                                </div>
                            )}
                        </div>

                        {selectedCamera ? (
                            <CameraPreview cameraName={selectedCamera} />
                        ) : (
                            <div className="aspect-video bg-gray-900 rounded-lg flex items-center justify-center text-gray-600 italic border border-dashed border-gray-700">
                                Select a camera to start preview
                            </div>
                        )}

                        <div className="mt-4 p-4 bg-blue-900/10 border border-blue-900/20 rounded-lg">
                            <p className="text-xs text-blue-300/80 leading-relaxed">
                                <b>Live View:</b> Images are automatically refreshed every 1 second.
                                If the camera is listed as "offline", ensure the ffmpeg service is running.
                            </p>
                        </div>
                    </div>
                </div>
            </div>
        </Layout>
    );
}
