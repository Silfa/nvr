import type { ReactNode } from 'react';
import { NavLink } from 'react-router-dom';

interface LayoutProps {
    children: ReactNode;
}

export function Layout({ children }: LayoutProps) {
    return (
        <div className="min-h-screen flex flex-col">
            <header className="bg-gray-800 border-b border-gray-700 p-4">
                <div className="container mx-auto flex items-center justify-between">
                    <h1 className="text-xl font-bold bg-gradient-to-r from-blue-400 to-teal-400 bg-clip-text text-transparent">
                        Home NVR
                    </h1>
                    <nav className="space-x-4">
                        <NavLink to="/" className={({ isActive }) => `transition ${isActive ? 'text-blue-400' : 'hover:text-blue-400'}`}>Dashboard</NavLink>
                        <NavLink to="/events" className={({ isActive }) => `transition ${isActive ? 'text-blue-400' : 'hover:text-blue-400'}`}>Events</NavLink>
                        <NavLink to="/settings" className={({ isActive }) => `transition ${isActive ? 'text-blue-400' : 'hover:text-blue-400'}`}>Settings</NavLink>
                    </nav>
                </div>
            </header>
            <main className="flex-1 container mx-auto p-4">
                {children}
            </main>
            <footer className="bg-gray-800 border-t border-gray-700 p-4 text-center text-sm text-gray-400">
                &copy; {new Date().getFullYear()} Home NVR System
            </footer>
        </div>
    );
}
