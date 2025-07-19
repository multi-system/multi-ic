import React from 'react';
import BasketDisplay from './components/BasketDisplay';
import MultiLogo from './assets/multi_logo.svg';
import './App.css';

function App() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 via-[#1a1a2e] to-gray-900">
      {/* Header */}
      <header className="bg-black bg-opacity-30 backdrop-blur-md border-b border-white border-opacity-10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center gap-3">
              <img src={MultiLogo} alt="Multi" className="h-8 w-8" />
              <h1 className="text-3xl font-bold text-white">Multi</h1>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="animate-fadeIn">
          <BasketDisplay />
        </div>
      </main>

      {/* Footer */}
      <footer className="mt-20 py-8 bg-black bg-opacity-30 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-center gap-2 text-gray-400 text-sm">
            <img src={MultiLogo} alt="Multi" className="h-5 w-5 opacity-60" />
            <p>Multi © 2025 - Built on the Internet Computer</p>
          </div>
        </div>
      </footer>
    </div>
  );
}

export default App;