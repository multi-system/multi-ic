import React, { useState } from 'react';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import BasketDisplay from './components/BasketDisplay';
import WalletSidebar from './components/WalletSidebar';
import { ToastContainer } from './components/Toast';
import MultiLogo from './assets/multi_logo.svg';
import './App.css';
import { SystemInfoProvider } from './contexts/SystemInfoContext';
import Footer from './components/Footer';

// Separate component to use the auth context
function AppContent() {
  const { isAuthenticated, principal, login, logout } = useAuth();
  const [walletOpen, setWalletOpen] = useState(false);

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 to-gray-900">
      {/* Header */}
      <header className="bg-black bg-opacity-30 backdrop-blur-md border-b border-white border-opacity-10">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center gap-3">
              <img src={MultiLogo} alt="Multi" className="h-8 w-8" />
              <h1 className="text-3xl font-bold text-white">Multi</h1>
            </div>

            {/* Auth Status */}
            <div className="flex items-center gap-4">
              {isAuthenticated ? (
                <>
                  <button
                    onClick={() => setWalletOpen(true)}
                    className="px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white font-medium rounded-lg transition-colors flex items-center gap-2"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z"
                      />
                    </svg>
                    Wallet
                  </button>
                  <div className="text-sm text-gray-400">
                    <span className="text-gray-500">Principal:</span>{' '}
                    <span
                      className="font-mono text-white cursor-pointer hover:text-[#586CE1] transition-colors"
                      onClick={() => {
                        navigator.clipboard.writeText(principal.toText());
                        // Optional: brief visual feedback
                        const el = document.createElement('div');
                        el.textContent = 'Copied!';
                        el.className =
                          'fixed top-20 right-4 bg-green-600 text-white px-3 py-1 rounded text-sm';
                        document.body.appendChild(el);
                        setTimeout(() => el.remove(), 1500);
                      }}
                      title="Click to copy full principal"
                    >
                      {principal?.toText().slice(0, 8)}...{principal?.toText().slice(-3)}
                    </span>
                  </div>
                  <button
                    onClick={logout}
                    className="px-4 py-2 text-sm font-medium text-gray-300 hover:text-white transition-colors"
                  >
                    Logout
                  </button>
                </>
              ) : (
                <button
                  onClick={login}
                  className="px-4 py-2 bg-[#586CE1] hover:bg-[#4056C7] text-white font-medium rounded-lg transition-colors"
                >
                  Connect
                </button>
              )}
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
      <Footer />

      {/* Wallet Sidebar */}
      <WalletSidebar isOpen={walletOpen} onClose={() => setWalletOpen(false)} />
    </div>
  );
}

// Main App component with AuthProvider
function App() {
  return (
    <AuthProvider>
      <SystemInfoProvider>
        <AppContent />
        <ToastContainer />
      </SystemInfoProvider>
    </AuthProvider>
  );
}

export default App;
