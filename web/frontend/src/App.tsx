import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { Dashboard } from './pages/Dashboard';
import { Events } from './pages/Events';
import { Settings } from './pages/Settings';

function App() {
  return (
    <BrowserRouter basename="/nvr">
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/events" element={<Events />} />
        <Route path="/settings" element={<Settings />} />
        {/* Placeholder for future routes */}
        <Route path="*" element={<Dashboard />} />
      </Routes>
    </BrowserRouter>
  );
}

export default App;
