import { useEffect, useState } from 'react';
import { Layout } from '../layouts/Layout';

interface CameraConfig {
    name: string;
    enabled?: boolean;
    motion?: {
        threshold?: number;
        min_area?: number;
        blur?: number;
        enabled?: boolean;
    };
    [key: string]: any;
}

export function Settings() {
    const [cameras, setCameras] = useState<CameraConfig[]>([]);
    const [selectedCam, setSelectedCam] = useState<string | null>(null);
    const [currentConfig, setCurrentConfig] = useState<CameraConfig | null>(null);
    const [saving, setSaving] = useState(false);
    const [message, setMessage] = useState<{ type: 'success' | 'error', text: string } | null>(null);
    const [maskExists, setMaskExists] = useState<boolean>(false);

    useEffect(() => {
        fetch('/nvr/api/cameras/')
            .then(res => res.json())
            .then(data => {
                setCameras(data);
                if (data.length > 0) {
                    setSelectedCam(data[0].name);
                    setCurrentConfig(JSON.parse(JSON.stringify(data[0])));
                }
            })
            .catch(err => console.error("Failed to fetch cameras", err));
    }, []);

    useEffect(() => {
        if (selectedCam) {
            checkMaskExists(selectedCam);
        }
    }, [selectedCam]);

    const checkMaskExists = async (name: string) => {
        try {
            const res = await fetch(`/nvr/api/cameras/${name}/mask`, { method: 'GET' });
            setMaskExists(res.ok);
        } catch (err) {
            setMaskExists(false);
        }
    };

    const handleSelectCamera = (name: string) => {
        const cam = cameras.find(c => c.name === name);
        if (cam) {
            setSelectedCam(name);
            setCurrentConfig(JSON.parse(JSON.stringify(cam))); // Deep copy
            setMessage(null);
        }
    };

    const handleUpdate = (path: string, value: any) => {
        if (!currentConfig) return;
        const newConfig = { ...currentConfig };
        const parts = path.split('.');
        let target: any = newConfig;
        for (let i = 0; i < parts.length - 1; i++) {
            if (!target[parts[i]]) target[parts[i]] = {};
            target = target[parts[i]];
        }
        target[parts[parts.length - 1]] = value;
        setCurrentConfig(newConfig);
    };

    const saveConfig = async () => {
        if (!selectedCam || !currentConfig) return;
        setSaving(true);
        setMessage(null);

        try {
            const res = await fetch(`/nvr/api/cameras/${selectedCam}/config`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(currentConfig)
            });
            const data = await res.json();
            if (data.error) {
                setMessage({ type: 'error', text: data.error });
            } else {
                setMessage({ type: 'success', text: 'Settings saved successfully.' });
                // Update local list
                setCameras(prev => prev.map(c => c.name === selectedCam ? currentConfig : c));
            }
        } catch (err) {
            setMessage({ type: 'error', text: 'Failed to save settings' });
        } finally {
            setSaving(false);
        }
    };

    const restartServices = async () => {
        if (!selectedCam) return;
        setSaving(true);
        setMessage(null);

        try {
            const res = await fetch(`/nvr/api/cameras/${selectedCam}/restart`, {
                method: 'POST'
            });
            await res.json();
            setMessage({ type: 'success', text: 'Services restart command sent.' });
        } catch (err) {
            setMessage({ type: 'error', text: 'Failed to restart services' });
        } finally {
            setSaving(false);
        }
    };

    return (
        <Layout>
            <div className="max-w-4xl mx-auto space-y-6">
                <h2 className="text-2xl font-bold text-gray-100">Camera Settings</h2>

                <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
                    {/* Camera List */}
                    <div className="md:col-span-1 border-r border-gray-700 pr-6 space-y-2">
                        {cameras.map(cam => (
                            <button
                                key={cam.name}
                                onClick={() => handleSelectCamera(cam.name)}
                                className={`w-full text-left p-3 rounded-lg border transition-all ${selectedCam === cam.name
                                    ? 'bg-blue-600/20 border-blue-500 text-blue-100'
                                    : 'bg-gray-900/50 border-gray-700 text-gray-400 hover:border-gray-500'
                                    }`}
                            >
                                {cam.name}
                            </button>
                        ))}
                    </div>

                    {/* Settings Form */}
                    <div className="md:col-span-3 space-y-6">
                        {currentConfig ? (
                            <div className="space-y-6">
                                <div className="bg-gray-800 rounded-xl p-6 border border-gray-700 shadow-sm space-y-8">
                                    <div>
                                        <h3 className="text-lg font-semibold mb-4 text-blue-400 border-b border-gray-700 pb-2">Motion Detection</h3>
                                        <div className="grid grid-cols-1 gap-6">
                                            <div className="space-y-2">
                                                <div className="flex justify-between items-center">
                                                    <label className="text-sm font-medium text-gray-300">Sensitivity Threshold</label>
                                                    <span className="text-xs text-blue-400 font-mono bg-blue-900/20 px-2 py-0.5 rounded">{currentConfig.motion?.threshold ?? 50}</span>
                                                </div>
                                                <input
                                                    type="range" min="1" max="255"
                                                    value={currentConfig.motion?.threshold ?? 50}
                                                    onChange={(e) => handleUpdate('motion.threshold', parseInt(e.target.value))}
                                                    className="w-full h-2 bg-gray-700 rounded-lg appearance-none cursor-pointer accent-blue-500"
                                                />
                                                <p className="text-xs text-gray-500">Lower = More sensitive to pixel brightness changes. (Default: 50)</p>
                                            </div>

                                            <div className="space-y-2">
                                                <div className="flex justify-between items-center">
                                                    <label className="text-sm font-medium text-gray-300">Minimum Area (Pixels)</label>
                                                    <span className="text-xs text-blue-400 font-mono bg-blue-900/20 px-2 py-0.5 rounded">{currentConfig.motion?.min_area ?? 500} px</span>
                                                </div>
                                                <input
                                                    type="number"
                                                    value={currentConfig.motion?.min_area ?? 500}
                                                    onChange={(e) => handleUpdate('motion.min_area', parseInt(e.target.value))}
                                                    className="w-full bg-gray-900 border border-gray-700 rounded px-3 py-2 text-sm text-gray-200 focus:border-blue-500 outline-none"
                                                />
                                                <p className="text-xs text-gray-500">How many pixels must change to trigger an event. Increase to ignore small movements. (Default: 500)</p>
                                            </div>

                                            <div className="flex items-center space-x-3">
                                                <input
                                                    type="checkbox"
                                                    id="motion-enabled"
                                                    checked={currentConfig.motion?.enabled !== false}
                                                    onChange={(e) => handleUpdate('motion.enabled', e.target.checked)}
                                                    className="w-4 h-4 rounded border-gray-700 bg-gray-900 text-blue-600 focus:ring-blue-500"
                                                />
                                                <label htmlFor="motion-enabled" className="text-sm text-gray-300 select-none">Enable Motion Detection</label>
                                            </div>
                                        </div>
                                    </div>

                                    <div className="pt-4 flex items-center justify-between">
                                        {message && (
                                            <div className={`text-sm ${message.type === 'success' ? 'text-green-400' : 'text-red-400'} animate-in fade-in`}>
                                                {message.text}
                                            </div>
                                        )}
                                        <button
                                            onClick={saveConfig}
                                            disabled={saving}
                                            className="ml-auto bg-blue-600 hover:bg-blue-500 disabled:bg-gray-700 text-white font-medium py-2 px-6 rounded-lg transition shadow-lg shadow-blue-900/20 flex items-center"
                                        >
                                            {saving ? 'Saving...' : 'Save Configuration'}
                                        </button>
                                    </div>
                                </div>

                                {/* Mask Management Section */}
                                <div className="bg-gray-800 rounded-xl p-6 border border-gray-700 shadow-sm">
                                    <h3 className="text-lg font-semibold mb-4 text-teal-400 border-b border-gray-700 pb-2">Motion Mask (Image-based)</h3>
                                    <p className="text-sm text-gray-400 mb-6">
                                        Upload a grayscale PNG image to ignore specific areas.
                                        <b>Black (0,0,0)</b> areas will be ignored. <b>White</b> areas will be watched.
                                    </p>

                                    <div className="space-y-4">
                                        <div className="flex items-center space-x-4 mb-2">
                                            <span className="text-sm font-medium text-gray-300">Current Status:</span>
                                            {maskExists ? (
                                                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                                                    Correctly Applied
                                                </span>
                                            ) : (
                                                <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
                                                    None
                                                </span>
                                            )}
                                        </div>

                                        <div className="flex flex-col sm:flex-row gap-4">
                                            <a
                                                href={`/nvr/api/cameras/${selectedCam}/latest`}
                                                target="_blank"
                                                rel="noopener noreferrer"
                                                className="bg-gray-700 hover:bg-gray-600 text-gray-200 py-2 px-4 rounded text-sm flex items-center justify-center transition"
                                            >
                                                <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                                                </svg>
                                                Download Template Image
                                            </a>

                                            {maskExists && (
                                                <a
                                                    href={`/nvr/api/cameras/${selectedCam}/mask`}
                                                    download={`${selectedCam}_mask.png`}
                                                    className="bg-teal-700 hover:bg-teal-600 text-white py-2 px-4 rounded text-sm flex items-center justify-center transition"
                                                >
                                                    <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                                                    </svg>
                                                    Download Current Mask
                                                </a>
                                            )}

                                            <label className="flex-1">
                                                <span className="sr-only">Choose mask file</span>
                                                <input
                                                    type="file"
                                                    accept="image/png"
                                                    onChange={async (e) => {
                                                        const file = e.target.files?.[0];
                                                        if (!file || !selectedCam) return;

                                                        const formData = new FormData();
                                                        formData.append('file', file);

                                                        setSaving(true);
                                                        try {
                                                            const res = await fetch(`/nvr/api/cameras/${selectedCam}/mask`, {
                                                                method: 'POST',
                                                                body: formData
                                                            });
                                                            await res.json();
                                                            setMessage({ type: 'success', text: 'Mask image uploaded successfully.' });
                                                            checkMaskExists(selectedCam); // Refresh status
                                                        } catch (err) {
                                                            setMessage({ type: 'error', text: 'Failed to upload mask.' });
                                                        } finally {
                                                            setSaving(false);
                                                        }
                                                    }}
                                                    className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded file:border-0 file:text-sm file:font-semibold file:bg-blue-600 file:text-white hover:file:bg-blue-500 transition"
                                                />
                                            </label>
                                        </div>
                                    </div>
                                </div>

                                {/* Service Control Section */}
                                <div className="bg-gray-800 rounded-xl p-6 border border-gray-700 shadow-sm">
                                    <h3 className="text-lg font-semibold mb-4 text-red-400 border-b border-gray-700 pb-2">Service Control</h3>
                                    <p className="text-sm text-gray-400 mb-6">
                                        Restart recording and motion detection services for this camera.
                                        Required after changing settings or to fix connection issues.
                                    </p>
                                    <button
                                        onClick={restartServices}
                                        disabled={saving}
                                        className="bg-red-900/20 hover:bg-red-900/40 border border-red-900/50 text-red-400 font-medium py-2 px-6 rounded-lg transition flex items-center"
                                    >
                                        {saving ? 'Processing...' : 'Restart All Camera Services'}
                                    </button>
                                </div>
                            </div>
                        ) : (
                            <div className="flex items-center justify-center h-64 border border-dashed border-gray-700 rounded-xl text-gray-500 italic">
                                Select a camera to view settings
                            </div>
                        )}
                    </div>
                </div>
            </div>
        </Layout>
    );
}
