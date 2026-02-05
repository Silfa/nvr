import { useEffect, useState } from 'react';
import { Layout } from '../layouts/Layout';
import { VideoPlayer } from '../components/VideoPlayer';

interface Event {
    event_id: string;
    camera: string;
    timestamp: string;
    duration_sec: number;
    jpeg_count: number;
    daynight: string;
    year: string;
    month: string;
    video_file: string | null;
    start_offset: number;
}

export function Events() {
    const [events, setEvents] = useState<Event[]>([]);
    const [loading, setLoading] = useState(true);
    const [selectedEvent, setSelectedEvent] = useState<Event | null>(null);
    const [cameraList, setCameraList] = useState<string[]>([]);
    const [filterCamera, setFilterCamera] = useState<string>('');
    const [filterDate, setFilterDate] = useState<string>(''); // YYYY-MM-DD
    const [filterStartTime, setFilterStartTime] = useState<string>(''); // HH:MM
    const [filterEndTime, setFilterEndTime] = useState<string>(''); // HH:MM
    const [eventFrames, setEventFrames] = useState<string[]>([]);
    const [enlargedImage, setEnlargedImage] = useState<string | null>(null);

    const fetchEvents = () => {
        setLoading(true);
        const params = new URLSearchParams();
        if (filterCamera) params.append('camera', filterCamera);
        if (filterDate) params.append('date', filterDate.replace(/-/g, ''));
        if (filterStartTime) params.append('start_time', filterStartTime.replace(/:/g, '') + '00');
        if (filterEndTime) params.append('end_time', filterEndTime.replace(/:/g, '') + '59');
        params.append('limit', '60');

        fetch(`/nvr/api/events/?${params.toString()}`)
            .then(res => res.json())
            .then(data => {
                setEvents(data);
                setLoading(false);
            })
            .catch(err => {
                console.error("Failed to fetch events", err);
                setLoading(false);
            });
    };

    useEffect(() => {
        fetchEvents();

        // Fetch camera list
        fetch('/nvr/api/cameras/')
            .then(res => res.json())
            .then(data => {
                setCameraList(data.map((c: any) => c.name));
            })
            .catch(err => console.error("Failed to fetch cameras", err));
    }, []);

    const fetchEventFrames = (ev: Event) => {
        fetch(`/nvr/api/events/${ev.camera}/${ev.year}/${ev.month}/${ev.event_id}/frames`)
            .then(res => res.json())
            .then(setEventFrames)
            .catch(err => console.error("Failed to fetch frames", err));
    };

    const handleEventSelect = (ev: Event) => {
        setSelectedEvent(ev);
        setEventFrames([]); // Clear old frames
        setEnlargedImage(null);
        fetchEventFrames(ev);
    };

    const handleDeleteEvent = async (e: React.MouseEvent, ev: Event) => {
        e.stopPropagation(); // Don't open player
        if (!window.confirm(`Delete event from ${new Date(ev.timestamp).toLocaleString()}?`)) return;

        try {
            const res = await fetch(`/nvr/api/events/${ev.camera}/${ev.year}/${ev.month}/${ev.event_id}`, {
                method: 'DELETE'
            });
            if (res.ok) {
                // Refresh list
                fetchEvents();
            } else {
                alert("Failed to delete event.");
            }
        } catch (err) {
            console.error("Delete error", err);
            alert("Error deleting event.");
        }
    };

    return (
        <Layout>
            <div className="space-y-6">
                <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
                    <h2 className="text-2xl font-bold text-gray-100">Motion Events</h2>
                    <div className="flex flex-wrap items-center gap-3 bg-gray-900/50 p-2 rounded-lg border border-gray-800">
                        <div className="flex items-center space-x-2">
                            <label className="text-xs text-gray-500 uppercase font-bold">Camera</label>
                            <select
                                value={filterCamera}
                                onChange={(e) => setFilterCamera(e.target.value)}
                                className="bg-gray-800 border border-gray-700 rounded px-3 py-1.5 text-sm text-gray-300 focus:border-blue-500 outline-none"
                            >
                                <option value="">All Cameras</option>
                                {cameraList.map(name => (
                                    <option key={name} value={name}>{name}</option>
                                ))}
                            </select>
                        </div>

                        <div className="flex items-center space-x-2">
                            <label className="text-xs text-gray-500 uppercase font-bold">Date</label>
                            <input
                                type="date"
                                value={filterDate}
                                onChange={(e) => setFilterDate(e.target.value)}
                                className="bg-gray-800 border border-gray-700 rounded px-3 py-1.5 text-sm text-gray-300 focus:border-blue-500 outline-none"
                            />
                        </div>

                        <div className="flex items-center space-x-2">
                            <label className="text-xs text-gray-500 uppercase font-bold">Time</label>
                            <div className="flex items-center bg-gray-800 border border-gray-700 rounded overflow-hidden">
                                <input
                                    type="time"
                                    value={filterStartTime}
                                    onChange={(e) => setFilterStartTime(e.target.value)}
                                    className="bg-transparent px-2 py-1.5 text-sm text-gray-300 focus:outline-none w-24"
                                />
                                <span className="text-gray-600 px-1">-</span>
                                <input
                                    type="time"
                                    value={filterEndTime}
                                    onChange={(e) => setFilterEndTime(e.target.value)}
                                    className="bg-transparent px-2 py-1.5 text-sm text-gray-300 focus:outline-none w-24"
                                />
                            </div>
                        </div>

                        <button
                            onClick={fetchEvents}
                            className="bg-blue-600 hover:bg-blue-500 text-white px-4 py-1.5 rounded text-sm font-medium transition shadow-lg shadow-blue-900/20"
                        >
                            Apply Filters
                        </button>

                        <button
                            onClick={() => {
                                setFilterCamera('');
                                setFilterDate('');
                                setFilterStartTime('');
                                setFilterEndTime('');
                                // fetchEvents will be called by useEffect if we added dependencies, 
                                // but for now let's just manually fetch after clear
                                setTimeout(fetchEvents, 0);
                            }}
                            className="bg-gray-800 hover:bg-gray-700 p-2 rounded border border-gray-700 text-gray-400 hover:text-white transition"
                            title="Clear & Refresh"
                        >
                            <svg xmlns="http://www.w3.org/2000/svg" className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                            </svg>
                        </button>
                    </div>
                </div>

                {loading ? (
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
                        {[...Array(8)].map((_, i) => (
                            <div key={i} className="bg-gray-800 rounded-lg h-64 animate-pulse border border-gray-700"></div>
                        ))}
                    </div>
                ) : events.length === 0 ? (
                    <div className="bg-gray-800 rounded-xl p-12 text-center border border-gray-700">
                        <p className="text-gray-500 italic">No events found.</p>
                    </div>
                ) : (
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
                        {events.map((ev) => (
                            <div
                                key={ev.event_id}
                                onClick={() => handleEventSelect(ev)}
                                className={`bg-gray-800 rounded-lg overflow-hidden border border-gray-700 transition-all group relative hover:border-blue-500 cursor-pointer`}
                            >
                                {/* Delete Button */}
                                <button
                                    onClick={(e) => handleDeleteEvent(e, ev)}
                                    className="absolute top-2 right-2 z-10 p-1.5 bg-red-600/20 hover:bg-red-600 text-red-500 hover:text-white rounded-full opacity-0 group-hover:opacity-100 transition-all shadow-lg backdrop-blur"
                                    title="Delete event"
                                >
                                    <svg xmlns="http://www.w3.org/2000/svg" className="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                                    </svg>
                                </button>

                                <div className="aspect-video bg-black relative overflow-hidden">
                                    <img
                                        src={`/nvr/api/events/${ev.camera}/${ev.year}/${ev.month}/${ev.event_id}/thumbnail`}
                                        alt="Event thumbnail"
                                        className="w-full h-full object-cover opacity-80 group-hover:opacity-100 transition-opacity"
                                    />
                                    {!ev.video_file && (
                                        <div className="absolute inset-0 flex items-center justify-center bg-black/40 text-[10px] text-gray-400">
                                            Video file missing
                                        </div>
                                    )}
                                    {ev.video_file && (
                                        <div className="absolute inset-0 flex items-center justify-center translate-y-4 group-hover:translate-y-0 opacity-0 group-hover:opacity-100 transition-all">
                                            <div className="bg-blue-600 p-2 rounded-full shadow-lg">
                                                <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
                                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                                                </svg>
                                            </div>
                                        </div>
                                    )}
                                    <div className="absolute top-2 left-2 bg-black/60 px-2 py-0.5 rounded text-[10px] text-white backdrop-blur whitespace-nowrap">
                                        {ev.camera}
                                    </div>
                                    <div className="absolute bottom-2 right-2 bg-black/60 px-2 py-0.5 rounded text-[10px] text-white backdrop-blur">
                                        {Math.round(ev.duration_sec)}s
                                    </div>
                                </div>
                                <div className="p-3">
                                    <div className="text-xs text-gray-400 font-mono mb-1">
                                        {new Date(ev.timestamp).toLocaleString()}
                                    </div>
                                    <div className="flex items-center justify-between text-[11px]">
                                        <span className="text-gray-500">{ev.jpeg_count} frames</span>
                                        <span className={`px-1.5 py-0.5 rounded ${ev.daynight === 'day' ? 'bg-orange-900/30 text-orange-400' : 'bg-blue-900/30 text-blue-400'}`}>
                                            {ev.daynight}
                                        </span>
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                )}
            </div>

            {/* Event Detail Modal */}
            {selectedEvent && (
                <div className="fixed inset-0 z-50 flex items-center justify-center p-4 md:p-8 bg-black/90 backdrop-blur-sm">
                    <div className="relative bg-gray-900 rounded-2xl w-full max-w-5xl max-h-[90vh] shadow-2xl flex flex-col border border-gray-800 animate-in fade-in zoom-in duration-200 overflow-hidden">

                        {/* Modal Header */}
                        <div className="p-4 border-b border-gray-800 flex items-center justify-between shrink-0">
                            <div>
                                <h3 className="text-lg font-bold text-white">Event Detail</h3>
                                <p className="text-xs text-gray-500 font-mono">
                                    {new Date(selectedEvent.timestamp).toLocaleString()} | {selectedEvent.camera}
                                </p>
                            </div>
                            <button
                                onClick={() => setSelectedEvent(null)}
                                className="p-2 hover:bg-gray-800 rounded-full text-gray-400 hover:text-white transition"
                            >
                                <svg xmlns="http://www.w3.org/2000/svg" className="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                                </svg>
                            </button>
                        </div>

                        <div className="flex-1 overflow-y-auto p-4 space-y-6">
                            {/* Main Display: Video or Enlarged Image */}
                            <div className="bg-black rounded-lg overflow-hidden aspect-video relative group border border-gray-800">
                                {enlargedImage ? (
                                    <div className="w-full h-full flex items-center justify-center">
                                        <img
                                            src={`/nvr/api/events/${selectedEvent.camera}/${selectedEvent.year}/${selectedEvent.month}/${selectedEvent.event_id}/frame/${enlargedImage}`}
                                            alt="Enlarged frame"
                                            className="max-w-full max-h-full object-contain"
                                        />
                                        <button
                                            onClick={() => setEnlargedImage(null)}
                                            className="absolute top-4 right-4 p-2 bg-black/60 rounded-full text-white hover:bg-black transition"
                                        >
                                            <span className="text-xs font-bold px-2 italic">Back to Video</span>
                                        </button>
                                    </div>
                                ) : (
                                    selectedEvent.video_file ? (
                                        <VideoPlayer
                                            cameraName={selectedEvent.camera}
                                            filename={selectedEvent.video_file}
                                            startOffset={selectedEvent.start_offset}
                                            onClose={() => setSelectedEvent(null)}
                                        />
                                    ) : (
                                        <div className="w-full h-full flex items-center justify-center text-gray-500 italic">
                                            Video file not available
                                        </div>
                                    )
                                )}
                            </div>

                            {/* Frame Gallery */}
                            <div className="space-y-3 pb-4">
                                <h4 className="text-sm font-bold text-gray-400 flex flex-wrap items-center gap-2">
                                    <span>Captured Frames</span>
                                    <span className="text-[10px] bg-blue-900/30 text-blue-400 px-2 py-0.5 rounded border border-blue-800/30">
                                        {new Date(selectedEvent.timestamp).toLocaleTimeString()}
                                    </span>
                                    <span className="text-[10px] bg-gray-800 px-2 py-0.5 rounded text-gray-500">{eventFrames.length} total</span>
                                </h4>
                                <div className="grid grid-cols-3 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-6 gap-3">
                                    {eventFrames.map((frame) => (
                                        <div
                                            key={frame}
                                            onClick={() => setEnlargedImage(frame)}
                                            className={`aspect-video bg-gray-800 rounded-md overflow-hidden border-2 cursor-pointer transition-all hover:scale-105 ${enlargedImage === frame ? 'border-blue-500 shadow-lg shadow-blue-900/40' : 'border-transparent hover:border-gray-600'}`}
                                        >
                                            <img
                                                src={`/nvr/api/events/${selectedEvent.camera}/${selectedEvent.year}/${selectedEvent.month}/${selectedEvent.event_id}/frame/${frame}`}
                                                alt={frame}
                                                className="w-full h-full object-cover"
                                                loading="lazy"
                                            />
                                        </div>
                                    ))}
                                    {eventFrames.length === 0 && (
                                        <div className="col-span-full h-24 flex items-center justify-center text-gray-700 bg-gray-900/30 rounded-lg border border-dashed border-gray-800 italic text-sm">
                                            Loading frames...
                                        </div>
                                    )}
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            )}
        </Layout>
    );
}
